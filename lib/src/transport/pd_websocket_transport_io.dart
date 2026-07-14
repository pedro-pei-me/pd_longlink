import 'dart:async';
import 'dart:io';

import '../pd_enums.dart';
import '../pd_event.dart';
import '../pd_logger.dart';
import '../pd_transport.dart';

class PDWebSocketTransportIO implements PDLongLinkTransport {
  final StreamController<PDLongLinkEvent> _events = StreamController<PDLongLinkEvent>.broadcast();

  WebSocket? _webSocket;
  PDLogger? _logger;
  bool _isConnected = false;
  bool _hasEmittedClose = false;

  @override
  Stream<PDLongLinkEvent> get events => _events.stream;

  @override
  bool get isConnected => _isConnected;

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
    _logger?.logDebug('PDWebSocketTransportIO', '=== Starting connection ===');
    _logger?.logDebug('PDWebSocketTransportIO', 'URI: $uri');
    _logger?.logDebug('PDWebSocketTransportIO', 'Headers: $headers');
    _logger?.logDebug('PDWebSocketTransportIO', 'Timeout: ${connectTimeout.inSeconds}s');

    _hasEmittedClose = false;
    _isConnected = false;
    await disconnect(silent: true);

    try {
      _logger?.logDebug('PDWebSocketTransportIO', 'Creating WebSocket...');
      _webSocket = await WebSocket.connect(
        uri.toString(),
        headers: headers,
      ).timeout(connectTimeout);
      _logger?.logDebug('PDWebSocketTransportIO', 'WebSocket created successfully');

      if (!_events.isClosed) {
        _events.add(const PDLongLinkEvent(type: PDLongLinkEventType.open));
      }
      _isConnected = true;

      _webSocket!.listen(
        (message) {
          if (message is String) {
            _logger?.logDebug('PDWebSocketTransportIO', 'onMessage triggered: String');
            if (!_events.isClosed) {
              _events.add(PDLongLinkEvent(type: PDLongLinkEventType.message, text: message));
            }
          } else if (message is List<int>) {
            _logger?.logDebug('PDWebSocketTransportIO', 'onMessage triggered: ${message.length} bytes');
            if (!_events.isClosed) {
              _events.add(PDLongLinkEvent(type: PDLongLinkEventType.message, binary: message));
            }
          }
        },
        onError: (error) {
          _logger?.logError('PDWebSocketTransportIO', 'onError triggered', error: error);
          if (!_events.isClosed) {
            _events.add(PDLongLinkEvent(type: PDLongLinkEventType.error, error: error));
          }
        },
        onDone: () {
          _logger?.logDebug('PDWebSocketTransportIO',
              'onDone triggered: closeCode=${_webSocket?.closeCode}, closeReason=${_webSocket?.closeReason}');
          _isConnected = false;
          if (!_hasEmittedClose && !_events.isClosed) {
            _hasEmittedClose = true;
            _events.add(PDLongLinkEvent(
              type: PDLongLinkEventType.close,
              closeCode: _webSocket?.closeCode,
              closeReason: _webSocket?.closeReason,
            ));
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      _logger?.logError('PDWebSocketTransportIO', 'Connection exception', error: e);
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<void> sendText(String text) async {
    if (_webSocket == null || !isConnected) {
      throw const PDLongLinkTransportException('Not connected');
    }
    _logger?.logDebug('PDWebSocketTransportIO', 'Sending text: $text');
    _webSocket!.add(text);
  }

  @override
  Future<void> sendBinary(List<int> bytes) async {
    if (_webSocket == null || !isConnected) {
      throw const PDLongLinkTransportException('Not connected');
    }
    _logger?.logDebug('PDWebSocketTransportIO', 'Sending binary: ${bytes.length} bytes');
    _webSocket!.add(bytes);
  }

  @override
  Future<void> disconnect({int? closeCode, String? closeReason, bool silent = false}) async {
    _logger?.logDebug('PDWebSocketTransportIO', 'Disconnecting: closeCode=$closeCode, closeReason=$closeReason, silent=$silent');
    _isConnected = false;
    try {
      _webSocket?.close(closeCode ?? 1000, closeReason);
    } catch (_) {}
    _webSocket = null;
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

PDWebSocketTransportIO createWebSocketTransport() {
  return PDWebSocketTransportIO();
}
