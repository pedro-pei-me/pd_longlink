import 'dart:async';
import 'dart:html' as html;
import 'dart:html';
import 'dart:typed_data';

import '../pd_long_link_core.dart';
import '../pd_logger.dart';

class PDWebSocketTransportWeb implements PDLongLinkTransport {
  final StreamController<PDLongLinkEvent> _events = StreamController<PDLongLinkEvent>.broadcast();

  html.WebSocket? _webSocket;
  PDLogger? _logger;
  StreamSubscription<Event>? _onOpenSub;
  StreamSubscription<Event>? _onErrorSub;
  StreamSubscription<MessageEvent>? _onMessageSub;
  StreamSubscription<CloseEvent>? _onCloseSub;
  bool _hasEmittedClose = false;

  @override
  Stream<PDLongLinkEvent> get events => _events.stream;

  @override
  bool get isConnected => _webSocket != null && _webSocket!.readyState == html.WebSocket.OPEN;

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
    _logger?.logDebug('PDWebSocketTransportWeb', '=== Starting connection ===');
    _logger?.logDebug('PDWebSocketTransportWeb', 'URI: $uri');
    _logger?.logDebug('PDWebSocketTransportWeb', 'Headers: $headers');
    _logger?.logDebug('PDWebSocketTransportWeb', 'Timeout: ${connectTimeout.inSeconds}s');

    await disconnect(silent: true);

    try {
      _logger?.logDebug('PDWebSocketTransportWeb', 'Creating WebSocket...');
      _webSocket = html.WebSocket(uri.toString());

      final completer = Completer<void>();
      Timer? timeoutTimer;

      _onOpenSub = _webSocket!.onOpen.listen((_) {
        timeoutTimer?.cancel();
        _logger?.logDebug('PDWebSocketTransportWeb', 'WebSocket created successfully');
        if (!_events.isClosed) {
          _events.add(const PDLongLinkEvent(type: PDLongLinkEventType.open));
        }
        completer.complete();
      });

      _onErrorSub = _webSocket!.onError.listen((error) {
        timeoutTimer?.cancel();
        _logger?.logError('PDWebSocketTransportWeb', 'WebSocket error', error: error);
        completer.completeError(error);
      });

      timeoutTimer = Timer(connectTimeout, () {
        _logger?.logError('PDWebSocketTransportWeb', 'WebSocket connection timeout');
        completer.completeError(TimeoutException('Connection timeout'));
        disconnect();
      });

      _onMessageSub = _webSocket!.onMessage.listen((event) {
        final data = event.data;
        if (data is String) {
          _logger?.logDebug('PDWebSocketTransportWeb', 'onMessage triggered: String');
          if (!_events.isClosed) {
            _events.add(PDLongLinkEvent(type: PDLongLinkEventType.message, text: data));
          }
        } else if (data is List<int>) {
          _logger?.logDebug('PDWebSocketTransportWeb', 'onMessage triggered: ${data.length} bytes');
          if (!_events.isClosed) {
            _events.add(PDLongLinkEvent(type: PDLongLinkEventType.message, binary: data));
          }
        } else if (data is ByteBuffer) {
          _logger?.logDebug('PDWebSocketTransportWeb', 'onMessage triggered: ByteBuffer');
          if (!_events.isClosed) {
            _events.add(PDLongLinkEvent(type: PDLongLinkEventType.message, binary: data.asUint8List()));
          }
        }
      });

      _onCloseSub = _webSocket!.onClose.listen((event) {
        _logger?.logDebug('PDWebSocketTransportWeb', 'onClose triggered: code=${event.code}, reason=${event.reason}');
        if (!_hasEmittedClose && !_events.isClosed) {
          _hasEmittedClose = true;
          _events.add(PDLongLinkEvent(
            type: PDLongLinkEventType.close,
            closeCode: event.code,
            closeReason: event.reason,
          ));
        }
      });

      await completer.future;
    } catch (e) {
      _logger?.logError('PDWebSocketTransportWeb', 'Connection exception', error: e);
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<void> sendText(String text) async {
    if (_webSocket == null || !isConnected) {
      throw const PDLongLinkTransportException('Not connected');
    }
    _logger?.logDebug('PDWebSocketTransportWeb', 'Sending text: $text');
    _webSocket!.send(text);
  }

  @override
  Future<void> sendBinary(List<int> bytes) async {
    if (_webSocket == null || !isConnected) {
      throw const PDLongLinkTransportException('Not connected');
    }
    _logger?.logDebug('PDWebSocketTransportWeb', 'Sending binary: ${bytes.length} bytes');
    _webSocket!.send(Uint8List.fromList(bytes));
  }

  @override
  Future<void> disconnect({int? closeCode, String? closeReason, bool silent = false}) async {
    _logger?.logDebug('PDWebSocketTransportWeb', 'Disconnecting: closeCode=$closeCode, closeReason=$closeReason');
    try {
      _webSocket?.close(closeCode ?? 1000, closeReason);
    } catch (_) {}
    _webSocket = null;
    await _onOpenSub?.cancel();
    _onOpenSub = null;
    await _onErrorSub?.cancel();
    _onErrorSub = null;
    await _onMessageSub?.cancel();
    _onMessageSub = null;
    await _onCloseSub?.cancel();
    _onCloseSub = null;
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

PDWebSocketTransportWeb createWebSocketTransport() {
  return PDWebSocketTransportWeb();
}
