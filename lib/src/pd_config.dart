import 'dart:math';

import 'pd_enums.dart';
import 'pd_logger.dart';

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