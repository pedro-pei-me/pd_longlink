import 'dart:math';

import 'pd_enums.dart';

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