import 'pd_enums.dart';
import 'pd_event.dart';
import 'pd_logger.dart';

/// 长连接传输层抽象接口。
///
/// 定义了所有传输实现必须实现的方法，包括连接、发送消息、断开连接等。
abstract class PDLongLinkTransport {
  /// 事件流，用于接收传输层产生的事件
  Stream<PDLongLinkEvent> get events;

  /// 建立连接。
  ///
  /// [uri] 连接地址；
  /// [headers] 请求头；
  /// [connectTimeout] 连接超时时间；
  /// [logger] 日志实例。
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
  /// [closeCode] WebSocket 关闭码；
  /// [closeReason] 关闭原因。
  Future<void> disconnect({int? closeCode, String? closeReason});

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
  /// [message] 异常消息；
  /// [errorCode] 可选的错误码。
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