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

/// 消息队列溢出策略枚举。
enum PDMessageQueueOverflowStrategy {
  /// 丢弃最旧的消息
  dropOldest,

  /// 丢弃最新的消息
  dropNewest,
}