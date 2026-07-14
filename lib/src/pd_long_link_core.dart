import 'dart:math';

import 'pd_logger.dart';

/// 长连接客户端的状态枚举。
enum PDLongLinkState {
  /// 未连接状态
  disconnected,

  /// 正在连接中
  connecting,

  /// 已连接
  connected,

  /// 正在重连中
  reconnecting,

  /// 连接失败（超过最大重连次数）
  failed,
}

/// 长连接事件类型枚举。
enum PDLongLinkEventType {
  /// 连接已建立
  open,

  /// 连接已关闭
  close,

  /// 收到消息
  message,

  /// 发生错误
  error,

  /// 发送心跳
  ping,

  /// 收到心跳响应
  pong,
}

/// 传输模式枚举。
enum PDLongLinkTransportMode {
  /// 自动选择传输模式（Web 使用 WebSocket，移动端使用系统 WebSocket）
  auto,

  /// 使用 dart:io 的 WebSocket 实现
  io,

  /// 使用系统 WebSocket（Android/iOS）
  system,

  /// 使用 Server-Sent Events（SSE）
  sse,
}

/// 错误码枚举。
enum PDLongLinkErrorCode {
  /// 未知错误
  unknown,

  /// 连接超时
  connectionTimeout,

  /// 认证失败
  authenticationFailed,

  /// 网络不可用
  networkUnavailable,

  /// 协议错误
  protocolError,

  /// 心跳超时
  heartbeatTimeout,

  /// 连接已关闭
  connectionClosed,

  /// 发送失败
  sendFailed,

  /// 客户端已释放
  clientDisposed,

  /// 达到最大重连次数
  maxReconnectAttemptsReached,
}

/// 长连接事件数据类。
///
/// 封装了所有可能的长连接事件信息，包括消息内容、错误信息和关闭原因等。
class PDLongLinkEvent {
  /// 事件类型
  final PDLongLinkEventType type;

  /// 文本消息内容
  final String? text;

  /// 二进制消息内容
  final List<int>? binary;

  /// 错误对象
  final Object? error;

  /// 错误码
  final PDLongLinkErrorCode? errorCode;

  /// WebSocket 关闭码
  final int? closeCode;

  /// WebSocket 关闭原因
  final String? closeReason;

  /// 创建长连接事件。
  ///
  /// [type] 为必填的事件类型，其他字段根据事件类型可选。
  const PDLongLinkEvent({
    required this.type,
    this.text,
    this.binary,
    this.error,
    this.errorCode,
    this.closeCode,
    this.closeReason,
  });

  @override
  String toString() {
    final textLength = text?.length ?? 0;
    final displayText = text != null ? text!.substring(0, min(textLength, 50)) : null;
    return 'PDLongLinkEvent{type: $type, text: $displayText${textLength > 50 ? '...' : ''}, error: $error, errorCode: $errorCode, closeCode: $closeCode}';
  }
}

/// 重连策略配置类。
///
/// 使用指数退避算法计算重连延迟，并支持抖动避免惊群效应。
class PDReconnectPolicy {
  /// 最大重连次数，默认 10 次
  final int maxAttempts;

  /// 基础延迟时间，默认 1 秒
  final Duration baseDelay;

  /// 最大延迟时间，默认 30 秒
  final Duration maxDelay;

  /// 抖动比例，默认 0.1（10%）
  final double jitterRatio;

  /// 是否在后台继续重连，默认 true
  final bool enableInBackground;

  /// 应用恢复前台时是否重连，默认 true
  final bool reconnectOnResume;

  /// 连接断开时是否自动重连，默认 true
  final bool reconnectOnDisconnect;

  static final Random _random = Random();

  /// 创建重连策略。
  ///
  /// [maxAttempts] 最大重连次数；[baseDelay] 基础延迟；[maxDelay] 最大延迟；
  /// [jitterRatio] 抖动比例（0-1）；[enableInBackground] 后台重连；
  /// [reconnectOnResume] 前台恢复重连；[reconnectOnDisconnect] 断开自动重连。
  const PDReconnectPolicy({
    this.maxAttempts = 10,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.jitterRatio = 0.1,
    this.enableInBackground = true,
    this.reconnectOnResume = true,
    this.reconnectOnDisconnect = true,
  });

  /// 根据重连次数计算延迟时间。
  ///
  /// 使用指数退避算法：baseDelay * 2^attempt，并应用抖动和上限限制。
  Duration getDelay(int attempt) {
    final delay = baseDelay * (1 << attempt);
    final jitter = delay * jitterRatio;
    final randomized = delay + Duration(milliseconds: (jitter.inMilliseconds * (2 * _random.nextDouble() - 1)).round());
    final clamped = randomized.inMilliseconds.clamp(baseDelay.inMilliseconds, maxDelay.inMilliseconds);
    return Duration(milliseconds: clamped);
  }
}

/// 心跳配置类。
///
/// 配置心跳包的发送间隔、超时时间和消息内容。
class PDHeartbeatConfig {
  /// 心跳发送间隔，默认 30 秒
  final Duration interval;

  /// 心跳超时时间，默认 10 秒
  final Duration timeout;

  /// 心跳请求消息，默认 'ping'
  final String pingMessage;

  /// 心跳响应消息，默认 'pong'
  final String pongMessage;

  /// 创建心跳配置。
  ///
  /// [interval] 心跳发送间隔；[timeout] 等待响应超时时间；
  /// [pingMessage] 发送的心跳消息；[pongMessage] 期望的响应消息。
  const PDHeartbeatConfig({
    this.interval = const Duration(seconds: 30),
    this.timeout = const Duration(seconds: 10),
    this.pingMessage = 'ping',
    this.pongMessage = 'pong',
  });
}

/// SSE 配置类。
///
/// 配置 Server-Sent Events 的请求方法、请求体、事件类型过滤等参数。
class PDSseConfig {
  /// HTTP 请求方法，默认 'GET'
  final String method;

  /// POST 请求的请求体
  final Map<String, dynamic>? body;

  /// 过滤的事件类型列表，为空则接收所有事件
  final List<String>? eventTypes;

  /// 是否解析 SSE 格式，默认 true
  final bool parseSseFormat;

  /// 上次事件 ID，用于断点续传
  final String? lastEventId;

  /// 重试延迟时间
  final Duration? retryDelay;

  /// 创建 SSE 配置。
  ///
  /// [method] HTTP 方法；[body] POST 请求体；[eventTypes] 事件类型过滤；
  /// [parseSseFormat] 是否解析 SSE 格式；[lastEventId] 上次事件 ID；[retryDelay] 重试延迟。
  const PDSseConfig({
    this.method = 'GET',
    this.body,
    this.eventTypes,
    this.parseSseFormat = true,
    this.lastEventId,
    this.retryDelay,
  });

  @override
  String toString() {
    return 'PDSseConfig{method: $method, parseSseFormat: $parseSseFormat, lastEventId: $lastEventId, retryDelay: $retryDelay}';
  }
}

/// 消息队列溢出策略枚举。
enum PDMessageQueueOverflowStrategy {
  /// 丢弃最旧的消息
  dropOldest,

  /// 丢弃最新的消息
  dropNewest,
}

/// 消息队列配置类。
///
/// 配置离线消息队列的启用状态、最大容量和溢出策略。
class PDMessageQueueConfig {
  /// 是否启用消息队列，默认 false
  final bool enabled;

  /// 队列最大容量，默认 100
  final int maxSize;

  /// 溢出策略，默认丢弃最旧消息
  final PDMessageQueueOverflowStrategy overflowStrategy;

  /// 创建消息队列配置。
  ///
  /// [enabled] 是否启用；[maxSize] 最大容量；[overflowStrategy] 溢出策略。
  const PDMessageQueueConfig({
    this.enabled = false,
    this.maxSize = 100,
    this.overflowStrategy = PDMessageQueueOverflowStrategy.dropOldest,
  });
}

/// 长连接客户端配置类。
///
/// 包含连接地址、传输模式、超时设置、重连策略、心跳配置等所有参数。
class PDLongLinkConfig {
  /// 连接地址
  final Uri uri;

  /// 传输模式，默认自动选择
  final PDLongLinkTransportMode transportMode;

  /// 请求头
  final Map<String, String>? headers;

  /// 连接超时时间，默认 10 秒
  final Duration connectTimeout;

  /// 重连策略配置
  final PDReconnectPolicy reconnectPolicy;

  /// 心跳配置
  final PDHeartbeatConfig heartbeatConfig;

  /// 是否自动连接，默认 false
  final bool autoConnect;

  /// 是否启用心跳，默认 true
  final bool enableHeartbeat;

  /// SSE 专用配置（仅 transportMode 为 sse 时有效）
  final PDSseConfig? sseConfig;

  /// 消息队列配置
  final PDMessageQueueConfig messageQueueConfig;

  /// 自定义日志实例
  final PDLogger? logger;

  /// 创建长连接配置。
  ///
  /// [uri] 为必填的连接地址；其他参数均有默认值。
  const PDLongLinkConfig({
    required this.uri,
    this.transportMode = PDLongLinkTransportMode.auto,
    this.headers,
    this.connectTimeout = const Duration(seconds: 10),
    this.reconnectPolicy = const PDReconnectPolicy(),
    this.heartbeatConfig = const PDHeartbeatConfig(),
    this.autoConnect = false,
    this.enableHeartbeat = true,
    this.sseConfig,
    this.messageQueueConfig = const PDMessageQueueConfig(),
    this.logger,
  });
}

/// 长连接传输层抽象接口。
///
/// 定义了所有传输实现必须实现的方法，包括连接、发送消息、断开连接等。
abstract class PDLongLinkTransport {
  /// 事件流，用于接收传输层产生的事件
  Stream<PDLongLinkEvent> get events;

  /// 建立连接。
  ///
  /// [uri] 连接地址；[headers] 请求头；[connectTimeout] 连接超时时间；[logger] 日志实例。
  Future<void> connect({
    required Uri uri,
    required Map<String, String> headers,
    required Duration connectTimeout,
    PDLogger? logger,
  });

  /// 发送文本消息。
  Future<void> sendText(String text);

  /// 发送二进制消息。
  Future<void> sendBinary(List<int> bytes);

  /// 断开连接。
  ///
  /// [closeCode] WebSocket 关闭码；[closeReason] 关闭原因；[silent] 是否静默断开。
  Future<void> disconnect({int? closeCode, String? closeReason, bool silent = false});

  /// 是否已连接
  bool get isConnected;

  /// 上次事件 ID（SSE 模式下有效）
  String? get lastEventId => null;
}

/// 长连接传输异常类。
class PDLongLinkTransportException implements Exception {
  /// 异常消息
  final String message;

  /// 错误码
  final PDLongLinkErrorCode? errorCode;

  /// 创建传输异常。
  ///
  /// [message] 异常消息；[errorCode] 可选的错误码。
  const PDLongLinkTransportException(this.message, {this.errorCode});

  @override
  String toString() => 'PDLongLinkTransportException: $message';
}

/// PDLongLinkTransport 的扩展方法。
///
/// 提供 SSE 专用的 serverRetryDelay 属性访问，保持与现有实现的兼容性。
extension PDLongLinkTransportExtension on PDLongLinkTransport {
  /// 服务器建议的重试延迟时间（仅 SSE 模式下有效）。
  ///
  /// 对于非 SSE 传输，返回 null。
  Duration? get serverRetryDelay {
    return null;
  }
}
