import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../pd_long_link_core.dart';
import '../pd_logger.dart';

class PDSseTransport implements PDLongLinkTransport {
  final StreamController<PDLongLinkEvent> _events = StreamController<PDLongLinkEvent>.broadcast();
  final PDSseConfig? _sseConfig;

  HttpClient? _client;
  HttpClientRequest? _request;
  HttpClientResponse? _response;
  StreamSubscription<String>? _streamSubscription;
  PDLogger? _logger;

  String? _currentEventId;
  String? _currentEventType;
  StringBuffer? _currentDataBuffer;
  bool _hasEmittedClose = false;
  Duration? _serverRetryDelay;

  @override
  Stream<PDLongLinkEvent> get events => _events.stream;

  @override
  bool get isConnected => _response != null && _response!.statusCode == HttpStatus.ok;

  PDSseTransport({PDSseConfig? sseConfig}) : _sseConfig = sseConfig;

  @override
  Future<void> connect({
    required Uri uri,
    required Map<String, String> headers,
    required Duration connectTimeout,
    PDLogger? logger,
  }) async {
    _logger = logger;
    _hasEmittedClose = false;
    _logger?.logDebug('PDSseTransport', '=== Starting connection ===');
    _logger?.logDebug('PDSseTransport', 'URI: $uri');
    _logger?.logDebug('PDSseTransport', 'Headers: $headers');
    _logger?.logDebug('PDSseTransport', 'Timeout: ${connectTimeout.inSeconds}s');
    _logger?.logDebug('PDSseTransport', 'SSE Config: ${_sseConfig?.toString()}');

    await disconnect(silent: true);

    try {
      _logger?.logDebug('PDSseTransport', 'Creating HTTP client...');
      _client = HttpClient();
      _client!.connectionTimeout = connectTimeout;

      _logger?.logDebug('PDSseTransport', 'Opening connection...');
      final method = _sseConfig?.method.toUpperCase() ?? 'GET';
      if (method == 'POST') {
        _request = await _client!.postUrl(uri);
        if (_sseConfig?.body != null) {
          _request!.headers.set('Content-Type', 'application/json');
          final bodyBytes = utf8.encode(json.encode(_sseConfig!.body));
          _request!.add(bodyBytes);
        }
      } else {
        _request = await _client!.getUrl(uri);
      }

      headers.forEach((key, value) {
        _request!.headers.add(key, value);
      });
      _request!.headers.set('Accept', 'text/event-stream');
      _request!.headers.set('Cache-Control', 'no-cache');
      if (_sseConfig?.lastEventId != null) {
        _request!.headers.set('Last-Event-ID', _sseConfig!.lastEventId!);
      }

      _logger?.logDebug('PDSseTransport', 'Sending request...');
      _response = await _request!.close();

      if (_response!.statusCode != HttpStatus.ok) {
        _logger?.logError('PDSseTransport', 'Connection failed with status: ${_response!.statusCode}');
        await disconnect(silent: true);
        throw PDLongLinkTransportException('HTTP ${_response!.statusCode}');
      }

      _logger?.logDebug('PDSseTransport', 'SSE connection established');
      if (!_events.isClosed) {
        _events.add(const PDLongLinkEvent(type: PDLongLinkEventType.open));
      }

      _streamSubscription = utf8.decoder.bind(_response!).transform(const LineSplitter()).listen((line) {
        if (_sseConfig?.parseSseFormat == false) {
          if (line.isNotEmpty && !_events.isClosed) {
            _events.add(PDLongLinkEvent(type: PDLongLinkEventType.message, text: line));
          }
        } else {
          _handleSseEvent(line);
        }
      }, onError: (error) {
        _logger?.logError('PDSseTransport', 'Stream error', error: error);
        if (!_events.isClosed) {
          _events.add(PDLongLinkEvent(type: PDLongLinkEventType.error, error: error));
        }
      }, onDone: () {
        _flushCurrentEvent();
        _logger?.logDebug('PDSseTransport', 'Stream closed');
        if (!_hasEmittedClose && !_events.isClosed) {
          _hasEmittedClose = true;
          _events.add(PDLongLinkEvent(
            type: PDLongLinkEventType.close,
            closeCode: _response?.statusCode,
          ));
        }
      });
    } catch (e) {
      _logger?.logError('PDSseTransport', 'Connection exception', error: e);
      await disconnect(silent: true);
      rethrow;
    }
  }

  void _handleSseEvent(String line) {
    if (line.isEmpty) {
      _flushCurrentEvent();
      return;
    }

    if (line.startsWith(':')) {
      return;
    }

    final colonIndex = line.indexOf(':');
    if (colonIndex == -1) {
      return;
    }

    final field = line.substring(0, colonIndex);
    String? value;
    if (colonIndex + 1 < line.length && line[colonIndex + 1] == ' ') {
      value = line.substring(colonIndex + 2);
    } else {
      value = line.substring(colonIndex + 1);
    }

    switch (field) {
      case 'event':
        _flushCurrentEvent();
        _currentEventType = value;
        break;
      case 'data':
        _currentDataBuffer ??= StringBuffer();
        if (_currentDataBuffer!.isNotEmpty) {
          _currentDataBuffer!.write('\n');
        }
        _currentDataBuffer!.write(value);
        break;
      case 'id':
        _currentEventId = value;
        break;
      case 'retry':
        try {
          final retryMs = int.parse(value);
          _serverRetryDelay = Duration(milliseconds: retryMs);
          _logger?.logDebug('PDSseTransport', 'Server requested retry delay: ${retryMs}ms');
        } catch (_) {}
        break;
    }
  }

  void _flushCurrentEvent() {
    if (_currentDataBuffer == null || _currentDataBuffer!.isEmpty) {
      return;
    }

    final data = _currentDataBuffer!.toString();
    final eventType = _currentEventType ?? 'message';

    if (_sseConfig?.eventTypes != null && _sseConfig!.eventTypes!.isNotEmpty) {
      if (!_sseConfig!.eventTypes!.contains(eventType)) {
        _currentDataBuffer = null;
        _currentEventType = null;
        return;
      }
    }

    _logger?.logDebug('PDSseTransport',
        'Received event: $eventType, data: ${data.substring(0, data.length > 50 ? 50 : data.length)}${data.length > 50 ? '...' : ''}');

    if (!_events.isClosed) {
      _events.add(PDLongLinkEvent(type: PDLongLinkEventType.message, text: data));
    }

    _currentDataBuffer = null;
    _currentEventType = null;
  }

  @override
  Future<void> sendText(String text) async {
    throw UnsupportedError('SSE is one-way communication, sendText is not supported');
  }

  @override
  Future<void> sendBinary(List<int> bytes) async {
    throw UnsupportedError('SSE is one-way communication, sendBinary is not supported');
  }

  @override
  Future<void> disconnect({int? closeCode, String? closeReason, bool silent = false}) async {
    _logger?.logDebug('PDSseTransport', 'Disconnecting...');
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _response = null;
    _request = null;
    _client?.close();
    _client = null;
    _currentEventId = null;
    _currentEventType = null;
    _currentDataBuffer = null;
    if (!silent && !_hasEmittedClose && !_events.isClosed) {
      _hasEmittedClose = true;
      _events.add(const PDLongLinkEvent(type: PDLongLinkEventType.close));
    }
  }

  @override
  String? get lastEventId => _currentEventId;
  Duration? get serverRetryDelay => _serverRetryDelay;
}

PDSseTransport createSseTransport({PDSseConfig? sseConfig}) {
  return PDSseTransport(sseConfig: sseConfig);
}
