import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../pd_enums.dart';
import '../pd_event.dart';
import '../pd_logger.dart';
import '../pd_transport.dart';

class PDSystemWebSocketTransport implements PDLongLinkTransport {
  static const MethodChannel _channel = MethodChannel('pd_longlink');
  static const EventChannel _eventChannel = EventChannel('pd_longlink/system_websocket_events');

  final PDLongLinkTransport? _fallback;
  final StreamController<PDLongLinkEvent> _events = StreamController<PDLongLinkEvent>.broadcast();

  StreamSubscription<dynamic>? _eventSub;
  StreamSubscription<PDLongLinkEvent>? _fallbackSub;

  int? _socketId;
  bool _useFallback = false;
  bool _hasEmittedClose = false;
  PDLogger? _logger;

  PDSystemWebSocketTransport({PDLongLinkTransport? fallback}) : _fallback = fallback;

  @override
  Stream<PDLongLinkEvent> get events => _events.stream;

  @override
  bool get isConnected {
    if (_useFallback) {
      return _fallback?.isConnected ?? false;
    }
    return _socketId != null;
  }

  @override
  String? get lastEventId => null;

  @override
  Future<void> connect({
    required Uri uri,
    required Map<String, String> headers,
    required Duration connectTimeout,
    PDLogger? logger,
  }) async {
    _logger = logger;
    _hasEmittedClose = false;
    await disconnect(silent: true);
    _useFallback = false;

    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
      _logger?.logDebug('PDSystemWebSocketTransport', 'Platform not supported (Android/iOS only), using fallback');
      await _connectFallback(
        uri: uri,
        headers: headers,
        connectTimeout: connectTimeout,
        cause: UnsupportedError('system websocket is only supported on Android/iOS'),
      );
      return;
    }

    try {
      _logger?.logDebug('PDSystemWebSocketTransport', 'Connecting via system WebSocket: $uri');
      final Map<dynamic, dynamic>? res = await _channel.invokeMapMethod<dynamic, dynamic>(
        'systemWebSocket.connect',
        <String, dynamic>{
          'url': uri.toString(),
          'headers': headers,
          'connectTimeoutMs': connectTimeout.inMilliseconds,
        },
      );
      final int? socketId = _toInt(res?['socketId']);
      if (socketId == null) {
        throw StateError('system websocket connect failed: missing socketId');
      }
      _socketId = socketId;
      _logger?.logDebug('PDSystemWebSocketTransport', 'System WebSocket connected, socketId=$socketId');

      final Stream<dynamic> eventStream = _eventChannel.receiveBroadcastStream();
      _eventSub = eventStream.listen(
        (dynamic e) => _handleNativeEvent(e),
        onError: (Object err) {
          _logger?.logError('PDSystemWebSocketTransport', 'Event channel error', error: err);
          if (!_events.isClosed) {
            _events.add(PDLongLinkEvent(type: PDLongLinkEventType.error, error: err));
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      _logger?.logWarning('PDSystemWebSocketTransport', 'System WebSocket connect failed, using fallback', error: e);
      await _connectFallback(uri: uri, headers: headers, connectTimeout: connectTimeout, cause: e);
    }
  }

  Future<void> _connectFallback({
    required Uri uri,
    required Map<String, String> headers,
    required Duration connectTimeout,
    required Object cause,
  }) async {
    if (_fallback == null) {
      throw cause;
    }
    _useFallback = true;
    await _fallbackSub?.cancel();
    _fallbackSub = _fallback!.events.listen((event) {
      if (!_events.isClosed) {
        _events.add(event);
      }
    }, onError: (Object e) {
      if (!_events.isClosed) {
        _events.add(PDLongLinkEvent(type: PDLongLinkEventType.error, error: e));
      }
    });
    await _fallback!.connect(uri: uri, headers: headers, connectTimeout: connectTimeout, logger: _logger);
  }

  void _handleNativeEvent(dynamic event) {
    final int? socketId = _socketId;
    if (socketId == null) {
      return;
    }

    if (event is! Map) {
      return;
    }

    final int? id = _toInt(event['socketId']);
    if (id != socketId) {
      return;
    }

    final String? type = event['type']?.toString();
    if (type == 'open') {
      _logger?.logDebug('PDSystemWebSocketTransport', 'Native WebSocket opened');
      if (!_events.isClosed) {
        _events.add(const PDLongLinkEvent(type: PDLongLinkEventType.open));
      }
      return;
    }
    if (type == 'message') {
      final isBinary = event['isBinary'] == true;
      if (isBinary) {
        final rawData = event['dataBytes'];
        List<int> bytes;
        if (rawData is List) {
          bytes = rawData.map((e) => (e is int) ? e : 0).toList();
        } else {
          bytes = [];
        }
        _logger?.logDebug('PDSystemWebSocketTransport', 'Native WebSocket binary message: ${bytes.length} bytes');
        if (!_events.isClosed) {
          _events.add(PDLongLinkEvent(type: PDLongLinkEventType.message, binary: bytes));
        }
      } else {
        final data = event['data']?.toString();
        _logger?.logDebug('PDSystemWebSocketTransport',
            'Native WebSocket message: ${data?.substring(0, data.length > 50 ? 50 : data.length)}${data != null && data.length > 50 ? '...' : ''}');
        if (!_events.isClosed) {
          _events.add(PDLongLinkEvent(type: PDLongLinkEventType.message, text: data));
        }
      }
      return;
    }
    if (type == 'error') {
      final error = event['error'] ?? event;
      _logger?.logError('PDSystemWebSocketTransport', 'Native WebSocket error', error: error);
      if (!_events.isClosed) {
        _events.add(PDLongLinkEvent(type: PDLongLinkEventType.error, error: error));
      }
      return;
    }
    if (type == 'closed') {
      final code = _toInt(event['code']);
      final reason = event['reason']?.toString();
      _logger?.logDebug('PDSystemWebSocketTransport', 'Native WebSocket closed: code=$code, reason=$reason');
      if (!_hasEmittedClose && !_events.isClosed) {
        _hasEmittedClose = true;
        _events.add(
          PDLongLinkEvent(
            type: PDLongLinkEventType.close,
            closeCode: code,
            closeReason: reason,
          ),
        );
      }
    }
  }

  int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  @override
  Future<void> sendText(String text) async {
    if (_useFallback) {
      await _fallback?.sendText(text);
      return;
    }
    final int? socketId = _socketId;
    if (socketId == null) {
      throw const PDLongLinkTransportException('Not connected');
    }
    _logger?.logDebug('PDSystemWebSocketTransport', 'Sending text via system WebSocket');
    await _channel.invokeMethod<void>('systemWebSocket.send', <String, dynamic>{'socketId': socketId, 'text': text});
  }

  @override
  Future<void> sendBinary(List<int> bytes) async {
    if (_useFallback) {
      await _fallback?.sendBinary(bytes);
      return;
    }
    final int? socketId = _socketId;
    if (socketId == null) {
      throw const PDLongLinkTransportException('Not connected');
    }
    _logger?.logDebug('PDSystemWebSocketTransport', 'Sending binary via system WebSocket: ${bytes.length} bytes');
    await _channel
        .invokeMethod<void>('systemWebSocket.sendBinary', <String, dynamic>{'socketId': socketId, 'bytes': bytes});
  }

  @override
  Future<void> disconnect({int? closeCode, String? closeReason, bool silent = false}) async {
    _logger?.logDebug('PDSystemWebSocketTransport', 'Disconnecting system WebSocket');
    if (_useFallback) {
      await _fallback?.disconnect(closeCode: closeCode, closeReason: closeReason);
      await _fallbackSub?.cancel();
      _fallbackSub = null;
      _useFallback = false;
      if (!silent && !_hasEmittedClose && !_events.isClosed) {
        _hasEmittedClose = true;
        _events.add(PDLongLinkEvent(
          type: PDLongLinkEventType.close,
          closeCode: closeCode,
          closeReason: closeReason,
        ));
      }
      return;
    }

    final int? socketId = _socketId;
    _socketId = null;

    await _eventSub?.cancel();
    _eventSub = null;

    if (socketId != null) {
      try {
        await _channel.invokeMethod<void>('systemWebSocket.close', <String, dynamic>{
          'socketId': socketId,
          'code': closeCode,
          'reason': closeReason,
        });
      } catch (_) {}
    }

    if (!silent && !_hasEmittedClose && !_events.isClosed) {
      _hasEmittedClose = true;
      _events.add(PDLongLinkEvent(
        type: PDLongLinkEventType.close,
        closeCode: closeCode,
        closeReason: closeReason,
      ));
    }
  }
}
