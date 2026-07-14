import 'dart:async';
import 'dart:html';

import '../pd_long_link_core.dart';
import '../pd_logger.dart';

class PDSseTransportWeb implements PDLongLinkTransport {
  final StreamController<PDLongLinkEvent> _events = StreamController<PDLongLinkEvent>.broadcast();
  final PDSseConfig? _sseConfig;

  EventSource? _eventSource;
  PDLogger? _logger;
  StreamSubscription<Event>? _onOpenSub;
  StreamSubscription<MessageEvent>? _onMessageSub;
  StreamSubscription<Event>? _onErrorSub;
  final Map<String, StreamSubscription<MessageEvent>> _customEventSubs = {};

  String? _currentEventId;
  bool _hasEmittedClose = false;

  @override
  Stream<PDLongLinkEvent> get events => _events.stream;

  @override
  bool get isConnected => _eventSource != null && _eventSource!.readyState == EventSource.OPEN;

  @override
  String? get lastEventId => _currentEventId;

  PDSseTransportWeb({PDSseConfig? sseConfig}) : _sseConfig = sseConfig;

  @override
  Future<void> connect({
    required Uri uri,
    required Map<String, String> headers,
    required Duration connectTimeout,
    PDLogger? logger,
  }) async {
    _logger = logger;
    _logger?.logDebug('PDSseTransportWeb', '=== Starting connection ===');
    _logger?.logDebug('PDSseTransportWeb', 'URI: $uri');
    _logger?.logDebug('PDSseTransportWeb', 'Headers: $headers');
    _logger?.logDebug('PDSseTransportWeb', 'Timeout: ${connectTimeout.inSeconds}s');
    _logger?.logDebug('PDSseTransportWeb', 'SSE Config: ${_sseConfig?.toString()}');

    if (headers.isNotEmpty) {
      _logger?.logWarning('PDSseTransportWeb', 'Custom headers are not supported on web SSE. Headers will be ignored.');
    }

    await disconnect(silent: true);

    _hasEmittedClose = false;

    try {
      _logger?.logDebug('PDSseTransportWeb', 'Creating EventSource...');

      final url = uri.toString();
      _eventSource = EventSource(url);

      final completer = Completer<void>();
      var completerCompleted = false;
      final timeoutTimer = Timer(connectTimeout, () {
        if (!completerCompleted) {
          completerCompleted = true;
          completer.completeError(
            TimeoutException('Connection timed out after ${connectTimeout.inSeconds}s', connectTimeout),
          );
        }
      });

      _onOpenSub = _eventSource!.onOpen.listen((_) {
        _logger?.logDebug('PDSseTransportWeb', 'EventSource opened');
        if (!completerCompleted) {
          completerCompleted = true;
          timeoutTimer.cancel();
          completer.complete();
        }
        if (!_events.isClosed) {
          _events.add(const PDLongLinkEvent(type: PDLongLinkEventType.open));
        }
      });

      _onMessageSub = _eventSource!.onMessage.listen((event) {
        _currentEventId = event.lastEventId;
        _logger?.logDebug('PDSseTransportWeb', 'Received message: ${event.data}');
        if (!_events.isClosed) {
          _events.add(PDLongLinkEvent(type: PDLongLinkEventType.message, text: event.data));
        }
      });

      if (_sseConfig?.eventTypes != null && _sseConfig!.eventTypes!.isNotEmpty) {
        for (final eventType in _sseConfig!.eventTypes!) {
          final provider = EventStreamProvider<MessageEvent>(eventType);
          final sub = provider.forTarget(_eventSource!).listen((event) {
            _currentEventId = event.lastEventId;
            _logger?.logDebug('PDSseTransportWeb', 'Received event [$eventType]: ${event.data}');
            if (!_events.isClosed) {
              _events.add(PDLongLinkEvent(type: PDLongLinkEventType.message, text: event.data));
            }
          });
          _customEventSubs[eventType] = sub;
        }
      }

      _onErrorSub = _eventSource!.onError.listen((error) {
        _logger?.logError('PDSseTransportWeb', 'EventSource error', error: error);
        if (!completerCompleted) {
          completerCompleted = true;
          timeoutTimer.cancel();
          completer.completeError(error);
        }
        if (!_events.isClosed) {
          _events.add(PDLongLinkEvent(type: PDLongLinkEventType.error, error: error));
        }
      });

      await completer.future;
    } catch (e) {
      _logger?.logError('PDSseTransportWeb', 'Connection exception', error: e);
      await disconnect(silent: true);
      rethrow;
    }
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
    _logger?.logDebug('PDSseTransportWeb', 'Disconnecting...');
    _eventSource?.close();
    _eventSource = null;
    await _onOpenSub?.cancel();
    _onOpenSub = null;
    await _onMessageSub?.cancel();
    _onMessageSub = null;
    await _onErrorSub?.cancel();
    _onErrorSub = null;
    for (final sub in _customEventSubs.values) {
      await sub.cancel();
    }
    _customEventSubs.clear();
    _currentEventId = null;
    if (!silent && !_hasEmittedClose && !_events.isClosed) {
      _hasEmittedClose = true;
      _events.add(const PDLongLinkEvent(type: PDLongLinkEventType.close));
    }
  }
}

PDLongLinkTransport createSseTransport({PDSseConfig? sseConfig}) {
  return PDSseTransportWeb(sseConfig: sseConfig);
}
