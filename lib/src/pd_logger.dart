import 'dart:developer' as developer;

import 'pd_log_types.dart';

/// 日志记录器类。
///
/// 支持按级别过滤日志，可自定义日志回调，支持实例级独立配置。
class PDLogger {
  /// 是否启用日志，默认 true
  bool enableLogging;

  /// 日志级别，默认 WARNING
  PDLogLevel logLevel;

  /// 自定义日志回调，为 null 时使用默认输出
  PDLogCallback? logCallback;

  /// 创建日志记录器。
  ///
  /// [enableLogging] 是否启用日志；
  /// [logLevel] 日志级别；
  /// [logCallback] 自定义回调。
  PDLogger({
    this.enableLogging = true,
    this.logLevel = PDLogLevel.warning,
    this.logCallback,
  });

  /// 记录错误级别日志。
  ///
  /// [module] 模块名；
  /// [message] 日志消息；
  /// [error] 错误对象；
  /// [stackTrace] 堆栈跟踪。
  void logError(
    String module,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(PDLogLevel.error, module, message, error, stackTrace);
  }

  /// 记录警告级别日志。
  ///
  /// [module] 模块名；
  /// [message] 日志消息；
  /// [error] 错误对象；
  /// [stackTrace] 堆栈跟踪。
  void logWarning(
    String module,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(PDLogLevel.warning, module, message, error, stackTrace);
  }

  /// 记录信息级别日志。
  ///
  /// [module] 模块名；
  /// [message] 日志消息。
  void logInfo(String module, String message) {
    _log(PDLogLevel.info, module, message, null, null);
  }

  /// 记录调试级别日志。
  ///
  /// [module] 模块名；
  /// [message] 日志消息。
  void logDebug(String module, String message) {
    _log(PDLogLevel.debug, module, message, null, null);
  }

  void _log(
    PDLogLevel level,
    String module,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (!enableLogging) {
      return;
    }

    if (!_shouldLog(level)) {
      return;
    }

    final logData = PDLogData(
      timestamp: DateTime.now(),
      level: level,
      module: module,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );

    if (logCallback != null) {
      try {
        logCallback!(logData);
      } catch (_) {}
    } else {
      developer.log(
        logData.message,
        name: logData.module,
        level: _levelToSeverity(logData.level),
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  bool _shouldLog(PDLogLevel level) {
    switch (logLevel) {
      case PDLogLevel.error:
        return level == PDLogLevel.error;
      case PDLogLevel.warning:
        return level == PDLogLevel.error || level == PDLogLevel.warning;
      case PDLogLevel.info:
        return level != PDLogLevel.debug;
      case PDLogLevel.debug:
        return true;
    }
  }

  static int _levelToSeverity(PDLogLevel level) {
    switch (level) {
      case PDLogLevel.error:
        return 4;
      case PDLogLevel.warning:
        return 3;
      case PDLogLevel.info:
        return 2;
      case PDLogLevel.debug:
        return 1;
    }
  }
}
