import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'pd_config.dart';
import 'pd_enums.dart';
import 'pd_event.dart';
import 'pd_logger.dart';
import 'pd_log_types.dart';
import 'pd_transport.dart';
import 'transport/pd_system_websocket_transport.dart';
import 'transport/pd_sse_transport_stub.dart'
    if (dart.library.io) 'transport/pd_sse_transport.dart'
    if (dart.library.html) 'transport/pd_sse_transport_web.dart';
import 'transport/pd_websocket_transport_stub.dart'
    if (dart.library.io) 'transport/pd_websocket_transport_io.dart'
    if (dart.library.html) 'transport/pd_websocket_transport_web.dart';

class _QueuedMessage {
  final String? text;
  final List<int>? binary;

  _QueuedMessage.text(this.text) : binary = null;
  _QueuedMessage.binary(this.binary) : text = null;
}

/// 长连接客户端核心类。
///
/// 提供 WebSocket/SSE 长连接的完整功能，包括连接管理、心跳保活、自动重连、消息队列等。
class PDLongLinkClient with WidgetsBindingObserver {
  final PDLongLinkConfig _config;
  late final PDLogger _logger;

  PDLongLinkTransport? _transport;
  PDLongLinkState _state = PDLongLinkState.disconnected;
  int _generation = 0;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _heartbeatTimeoutTimer;

  StreamSubscription<PDLongLinkEvent>? _transportEventSubscription;

  final StreamController<PDLongLinkState> _stateController = StreamController<PDLongLinkState>.broadcast(sync: true);
  final StreamController<PDLongLinkEvent> _eventController = StreamController<PDLongLinkEvent>.broadcast(sync: true);

  /// 状态变化流
  Stream<PDLongLinkState> get state => _stateController.stream;

  /// 事件流，包含消息、错误、连接状态变化等
  Stream<PDLongLinkEvent> get events => _eventController.stream;

  /// 当前连接状态
  PDLongLinkState get currentState => _state;

  String? _lastEventId;

  /// 上次事件 ID（SSE 模式下用于断点续传）
  String? get lastEventId => _lastEventId ?? _transport?.lastEventId;

  bool _isDisposed = false;
  final List<_QueuedMessage> _messageQueue = [];

  /// 创建长连接客户端。
  ///
  /// [config] 为必填配置。如果 [PDLongLinkConfig.autoConnect] 为 true，
  /// 构造函数中会自动调用 [connect] 方法。
  PDLongLinkClient({required PDLongLinkConfig config}) : _config = config {
    _logger = config.logger ?? PDLogger();
    _logger.logInfo('PDLongLinkClient', 'Client initialized: uri=${config.uri}, mode=${config.transportMode}');
    WidgetsBinding.instance.addObserver(this);
    if (_config.autoConnect) {
      connect();
    }
  }

  void _addEvent(PDLongLinkEvent event) {
    if (_isDisposed) return;
    try {
      _eventController.add(event);
    } catch (_) {}
  }

  void _updateState(PDLongLinkState newState) {
    if (_isDisposed) return;
    if (_state != newState) {
      _state = newState;
      _logger.logInfo('PDLongLinkClient', 'State changed to $newState');
      try {
        _stateController.add(newState);
      } catch (_) {}
    }
  }

  PDLongLinkTransport _createTransport() {
    final mode = _config.transportMode;

    if (mode == PDLongLinkTransportMode.sse) {
      PDSseConfig? sseConfig = _config.sseConfig;
      if (_lastEventId != null) {
        sseConfig = PDSseConfig(
          method: sseConfig?.method ?? 'GET',
          body: sseConfig?.body,
          eventTypes: sseConfig?.eventTypes,
          parseSseFormat: sseConfig?.parseSseFormat ?? true,
          lastEventId: _lastEventId,
          retryDelay: sseConfig?.retryDelay,
        );
      }
      return createSseTransport(sseConfig: sseConfig);
    }

    if (mode == PDLongLinkTransportMode.io) {
      return createWebSocketTransport();
    }

    if (mode == PDLongLinkTransportMode.system) {
      return PDSystemWebSocketTransport(fallback: createWebSocketTransport());
    }

    if (kIsWeb) {
      return createWebSocketTransport();
    }

    return PDSystemWebSocketTransport(fallback: createWebSocketTransport());
  }

  /// 建立与指定 URI 的长连接。
  ///
  /// 连接成功后会触发 [PDLongLinkEventType.open] 事件。
  /// 如果已处于连接或正在连接状态，调用会被忽略。
  /// 如果连接失败，会进入自动重连逻辑（如配置启用）。
  Future<void> connect() async {
    if (_isDisposed) return;
    if (_state == PDLongLinkState.connected) {
      _logger.logWarning('PDLongLinkClient', 'Already connected, ignore connect call');
      return;
    }
    if (_state == PDLongLinkState.connecting) {
      _logger.logWarning('PDLongLinkClient', 'Already connecting, ignore connect call');
      return;
    }

    _generation++;
    _reconnectAttempt = 0;
    final localGeneration = _generation;

    _cancelReconnectTimer();
    _stopHeartbeat();
    await _transportEventSubscription?.cancel();

    _updateState(PDLongLinkState.connecting);
    _logger.logInfo('PDLongLinkClient', 'Connecting to ${_config.uri}');

    try {
      _transport = _createTransport();
      _logger.logDebug('PDLongLinkClient', 'Transport created: ${_config.transportMode}');

      _transportEventSubscription = _transport!.events.listen((event) {
        if (_generation != localGeneration) {
          return;
        }

        _addEvent(event);

        switch (event.type) {
          case PDLongLinkEventType.open:
            _handleOpen(localGeneration);
            break;
          case PDLongLinkEventType.close:
            _handleClose(localGeneration);
            break;
          case PDLongLinkEventType.error:
            _handleError(localGeneration, event.error);
            break;
          case PDLongLinkEventType.pong:
            _handlePong();
            break;
          case PDLongLinkEventType.message:
            _handleMessage(event);
            break;
          default:
            break;
        }
      });

      await _transport!.connect(
        uri: _config.uri,
        headers: _config.headers ?? {},
        connectTimeout: _config.connectTimeout,
        logger: _logger,
      );
    } catch (e) {
      _logger.logError('PDLongLinkClient', 'Connect failed', error: e);
      _addEvent(PDLongLinkEvent(
        type: PDLongLinkEventType.error,
        error: e,
        errorCode: _classifyErrorCode(e),
      ));
      _handleError(localGeneration, e);
    }
  }

  PDLongLinkErrorCode _classifyErrorCode(Object? error) {
    if (error is TimeoutException) {
      return PDLongLinkErrorCode.connectionTimeout;
    }
    if (error is PDLongLinkTransportException) {
      if (error.message.contains('disposed')) {
        return PDLongLinkErrorCode.clientDisposed;
      }
      if (error.message.contains('Not connected')) {
        return PDLongLinkErrorCode.connectionClosed;
      }
      if (error.message.contains('send')) {
        return PDLongLinkErrorCode.sendFailed;
      }
    }
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
      return PDLongLinkErrorCode.connectionTimeout;
    }
    if (errorStr.contains('socket') || errorStr.contains('network') || errorStr.contains('connection refused')) {
      return PDLongLinkErrorCode.networkUnavailable;
    }
    if (errorStr.contains('auth') || errorStr.contains('401') || errorStr.contains('403')) {
      return PDLongLinkErrorCode.authenticationFailed;
    }
    return PDLongLinkErrorCode.unknown;
  }

  void _handleMessage(PDLongLinkEvent event) {
    if (_config.enableHeartbeat) {
      final pongMsg = _config.heartbeatConfig.pongMessage;
      if (event.text == pongMsg) {
        _handlePong();
      }
    }
  }

  void _handleOpen(int generation) {
    if (_generation != generation) {
      return;
    }

    _reconnectAttempt = 0;
    _cancelReconnectTimer();
    _updateState(PDLongLinkState.connected);
    _logger.logInfo('PDLongLinkClient', 'Connected successfully');

    if (_config.enableHeartbeat && _config.transportMode != PDLongLinkTransportMode.sse) {
      _startHeartbeat();
      _logger.logDebug('PDLongLinkClient', 'Heartbeat started, interval=${_config.heartbeatConfig.interval}');
    }

    _drainMessageQueue();
  }

  void _handleClose(int generation) {
    if (_generation != generation) {
      return;
    }

    _lastEventId = _transport?.lastEventId;
    _updateState(PDLongLinkState.disconnected);
    _stopHeartbeat();
    _logger.logInfo('PDLongLinkClient', 'Connection closed');

    if (_config.reconnectPolicy.reconnectOnDisconnect && !_isDisposed) {
      _scheduleReconnect();
    }
  }

  void _handleError(int generation, Object? error) {
    if (_generation != generation) {
      return;
    }

    _lastEventId = _transport?.lastEventId;
    _updateState(PDLongLinkState.disconnected);
    _stopHeartbeat();
    _logger.logError('PDLongLinkClient', 'Connection error', error: error);

    if (_config.reconnectPolicy.reconnectOnDisconnect && !_isDisposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed) return;
    if (_state == PDLongLinkState.connected) return;
    if (_state == PDLongLinkState.connecting) return;
    if (_state == PDLongLinkState.reconnecting) return;
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;
    if (_reconnectAttempt >= _config.reconnectPolicy.maxAttempts) {
      _updateState(PDLongLinkState.failed);
      _logger.logError('PDLongLinkClient', 'Max reconnect attempts reached (${_config.reconnectPolicy.maxAttempts})');
      _addEvent(const PDLongLinkEvent(
        type: PDLongLinkEventType.error,
        error: 'Max reconnect attempts reached',
        errorCode: PDLongLinkErrorCode.maxReconnectAttemptsReached,
      ));
      return;
    }

    final delay = _config.reconnectPolicy.getDelay(_reconnectAttempt);
    _reconnectAttempt++;

    _updateState(PDLongLinkState.reconnecting);
    _logger.logInfo('PDLongLinkClient',
        'Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempt/${_config.reconnectPolicy.maxAttempts})');

    _reconnectTimer = Timer(delay, () {
      connect();
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(_config.heartbeatConfig.interval, (_) {
      _sendPing();
    });
  }

  void _sendPing() async {
    if (_isDisposed) return;
    if (_state != PDLongLinkState.connected || _transport == null) {
      return;
    }

    try {
      await _transport!.sendText(_config.heartbeatConfig.pingMessage);
      _addEvent(const PDLongLinkEvent(type: PDLongLinkEventType.ping));

      _heartbeatTimeoutTimer?.cancel();
      _heartbeatTimeoutTimer = Timer(_config.heartbeatConfig.timeout, () {
        _addEvent(const PDLongLinkEvent(
          type: PDLongLinkEventType.error,
          error: 'Heartbeat timeout',
          errorCode: PDLongLinkErrorCode.heartbeatTimeout,
        ));
        disconnect();
      });
    } catch (e) {
      _addEvent(PDLongLinkEvent(
        type: PDLongLinkEventType.error,
        error: e,
        errorCode: PDLongLinkErrorCode.sendFailed,
      ));
    }
  }

  void _handlePong() {
    _heartbeatTimeoutTimer?.cancel();
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatTimeoutTimer?.cancel();
    _heartbeatTimeoutTimer = null;
  }

  // ===== Message Queue =====

  void _enqueueText(String text) {
    final config = _config.messageQueueConfig;
    if (!config.enabled) {
      throw const PDLongLinkTransportException('Not connected', errorCode: PDLongLinkErrorCode.connectionClosed);
    }
    if (_messageQueue.length >= config.maxSize) {
      switch (config.overflowStrategy) {
        case PDMessageQueueOverflowStrategy.dropOldest:
          _messageQueue.removeAt(0);
          break;
        case PDMessageQueueOverflowStrategy.dropNewest:
          return;
      }
    }
    _messageQueue.add(_QueuedMessage.text(text));
    _logger.logDebug('PDLongLinkClient', 'Message queued (queue size: ${_messageQueue.length})');
  }

  void _enqueueBinary(List<int> bytes) {
    final config = _config.messageQueueConfig;
    if (!config.enabled) {
      throw const PDLongLinkTransportException('Not connected', errorCode: PDLongLinkErrorCode.connectionClosed);
    }
    if (_messageQueue.length >= config.maxSize) {
      switch (config.overflowStrategy) {
        case PDMessageQueueOverflowStrategy.dropOldest:
          _messageQueue.removeAt(0);
          break;
        case PDMessageQueueOverflowStrategy.dropNewest:
          return;
      }
    }
    _messageQueue.add(_QueuedMessage.binary(bytes));
    _logger.logDebug('PDLongLinkClient', 'Binary message queued (queue size: ${_messageQueue.length})');
  }

  void _drainMessageQueue() {
    if (_messageQueue.isEmpty) return;
    if (_state != PDLongLinkState.connected || _transport == null) return;

    _logger.logInfo('PDLongLinkClient', 'Draining message queue (${_messageQueue.length} messages)');
    final messages = List<_QueuedMessage>.from(_messageQueue);
    _messageQueue.clear();

    for (final msg in messages) {
      try {
        if (msg.text != null) {
          _transport!.sendText(msg.text!);
        } else if (msg.binary != null) {
          _transport!.sendBinary(msg.binary!);
        }
      } catch (e) {
        _logger.logError('PDLongLinkClient', 'Failed to send queued message', error: e);
        _addEvent(PDLongLinkEvent(
          type: PDLongLinkEventType.error,
          error: e,
          errorCode: PDLongLinkErrorCode.sendFailed,
        ));
      }
    }
  }

  // ===== Public API =====

  /// 发送文本消息。
  ///
  /// 如果未连接且消息队列已启用，消息会被加入队列等待发送。
  /// 如果客户端已释放，会抛出 [PDLongLinkTransportException]。
  Future<void> sendText(String text) async {
    if (_isDisposed) {
      throw const PDLongLinkTransportException('Client disposed', errorCode: PDLongLinkErrorCode.clientDisposed);
    }
    if (_state != PDLongLinkState.connected || _transport == null) {
      _enqueueText(text);
      return;
    }
    await _transport!.sendText(text);
  }

  /// 发送二进制消息。
  ///
  /// 如果未连接且消息队列已启用，消息会被加入队列等待发送。
  /// 如果客户端已释放，会抛出 [PDLongLinkTransportException]。
  Future<void> sendBinary(List<int> bytes) async {
    if (_isDisposed) {
      throw const PDLongLinkTransportException('Client disposed', errorCode: PDLongLinkErrorCode.clientDisposed);
    }
    if (_state != PDLongLinkState.connected || _transport == null) {
      _enqueueBinary(bytes);
      return;
    }
    await _transport!.sendBinary(bytes);
  }

  /// 断开连接。
  ///
  /// [closeCode] WebSocket 关闭码；
  /// [closeReason] 关闭原因。
  Future<void> disconnect({int? closeCode, String? closeReason}) async {
    if (_isDisposed) return;

    _cancelReconnectTimer();
    _stopHeartbeat();
    await _transportEventSubscription?.cancel();

    _lastEventId = _transport?.lastEventId;
    _generation++;

    await _transport?.disconnect(closeCode: closeCode, closeReason: closeReason);
    _transport = null;

    _updateState(PDLongLinkState.disconnected);
  }

  /// 释放客户端资源。
  ///
  /// 调用后客户端将不可再使用。会清理所有定时器、订阅和控制器。
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;

    _cancelReconnectTimer();
    _stopHeartbeat();
    await _transportEventSubscription?.cancel();

    await _transport?.disconnect();
    _transport = null;

    _messageQueue.clear();

    WidgetsBinding.instance.removeObserver(this);

    try {
      await _stateController.close();
    } catch (_) {}
    try {
      await _eventController.close();
    } catch (_) {}
  }

  /// 设置日志级别。
  void setLogLevel(PDLogLevel level) {
    _logger.logLevel = level;
    _logger.logInfo('PDLongLinkClient', 'Log level updated to $level');
  }

  /// 启用或禁用日志。
  void enableLogging(bool enable) {
    _logger.enableLogging = enable;
    _logger.logInfo('PDLongLinkClient', 'Logging ${enable ? 'enabled' : 'disabled'}');
  }

  /// 设置自定义日志回调。
  void setLogCallback(PDLogCallback? callback) {
    _logger.logCallback = callback;
    _logger.logInfo('PDLongLinkClient', 'Log callback updated');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;

    switch (state) {
      case AppLifecycleState.resumed:
        if (_config.reconnectPolicy.reconnectOnResume && _state == PDLongLinkState.disconnected) {
          connect();
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        if (!_config.reconnectPolicy.enableInBackground) {
          disconnect();
        }
        break;
    }
  }
}
