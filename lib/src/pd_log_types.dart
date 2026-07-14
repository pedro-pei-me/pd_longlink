/// 日志级别枚举。
enum PDLogLevel {
  /// 错误级别，仅记录严重错误
  error,

  /// 警告级别，记录警告信息
  warning,

  /// 信息级别，记录重要事件
  info,

  /// 调试级别，记录详细调试信息
  debug,
}

/// PDLogLevel 的扩展方法。
extension PDLogLevelExtension on PDLogLevel {
  /// 获取日志级别的大写名称
  String get getName => name.toUpperCase();
}

/// 日志数据类。
///
/// 封装了一条日志的完整信息，包括时间戳、级别、模块、消息和错误信息。
class PDLogData {
  /// 日志时间戳
  final DateTime timestamp;

  /// 日志级别
  final PDLogLevel level;

  /// 日志来源模块
  final String module;

  /// 日志消息
  final String message;

  /// 错误对象
  final Object? error;

  /// 堆栈跟踪
  final StackTrace? stackTrace;

  /// 创建日志数据。
  ///
  /// [timestamp]、[level]、[module]、[message] 为必填参数。
  const PDLogData({
    required this.timestamp,
    required this.level,
    required this.module,
    required this.message,
    this.error,
    this.stackTrace,
  });

  @override
  String toString() {
    return '[${_formatTime(timestamp)}] [${_levelToString(level)}] [$module] $message${error != null ? ' - $error' : ''}';
  }

  String _formatTime(DateTime time) {
    return time.toIso8601String().split('T')[1].substring(0, 12);
  }

  String _levelToString(PDLogLevel level) {
    switch (level) {
      case PDLogLevel.error:
        return 'ERROR';
      case PDLogLevel.warning:
        return 'WARNING';
      case PDLogLevel.info:
        return 'INFO';
      case PDLogLevel.debug:
        return 'DEBUG';
    }
  }
}

/// 日志回调函数类型。
typedef PDLogCallback = void Function(PDLogData logData);
