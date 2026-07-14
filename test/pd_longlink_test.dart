import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pd_longlink/pd_longlink.dart';

// ===== Mock Transport for testing PDLongLinkClient =====

class MockTransport implements PDLongLinkTransport {
  final StreamController<PDLongLinkEvent> _events = StreamController<PDLongLinkEvent>.broadcast();

  bool _isConnected = false;
  String? _lastEventId;
  int connectCallCount = 0;
  int disconnectCallCount = 0;
  List<String> sentTexts = [];
  List<List<int>> sentBinaries = [];
  Uri? lastConnectUri;

  void simulateOpen() {
    _isConnected = true;
    if (!_events.isClosed) {
      _events.add(const PDLongLinkEvent(type: PDLongLinkEventType.open));
    }
  }

  void simulateClose({int? closeCode, String? closeReason}) {
    _isConnected = false;
    if (!_events.isClosed) {
      _events.add(PDLongLinkEvent(
        type: PDLongLinkEventType.close,
        closeCode: closeCode,
        closeReason: closeReason,
      ));
    }
  }

  void simulateError(Object error) {
    _isConnected = false;
    if (!_events.isClosed) {
      _events.add(PDLongLinkEvent(type: PDLongLinkEventType.error, error: error));
    }
  }

  void simulateMessage(String text) {
    if (!_events.isClosed) {
      _events.add(PDLongLinkEvent(type: PDLongLinkEventType.message, text: text));
    }
  }

  void simulateBinaryMessage(List<int> bytes) {
    if (!_events.isClosed) {
      _events.add(PDLongLinkEvent(type: PDLongLinkEventType.message, binary: bytes));
    }
  }

  @override
  Stream<PDLongLinkEvent> get events => _events.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  String? get lastEventId => _lastEventId;

  set lastEventId(String? value) => _lastEventId = value;

  @override
  Future<void> connect({
    required Uri uri,
    required Map<String, String> headers,
    required Duration connectTimeout,
    PDLogger? logger,
  }) async {
    lastConnectUri = uri;
    connectCallCount++;
  }

  @override
  Future<void> sendText(String text) async {
    if (!_isConnected) {
      throw const PDLongLinkTransportException('Not connected');
    }
    sentTexts.add(text);
  }

  @override
  Future<void> sendBinary(List<int> bytes) async {
    if (!_isConnected) {
      throw const PDLongLinkTransportException('Not connected');
    }
    sentBinaries.add(bytes);
  }

  @override
  Future<void> disconnect({int? closeCode, String? closeReason, bool silent = false}) async {
    _isConnected = false;
    disconnectCallCount++;
  }

  void dispose() {
    _events.close();
  }
}

// ===== Helper to create a test client with mock transport =====

PDLongLinkClient createTestClient({
  Uri? uri,
  PDLongLinkTransportMode transportMode = PDLongLinkTransportMode.io,
  bool enableHeartbeat = false,
  bool autoConnect = false,
  PDReconnectPolicy? reconnectPolicy,
  PDMessageQueueConfig? messageQueueConfig,
  PDHeartbeatConfig? heartbeatConfig,
}) {
  final config = PDLongLinkConfig(
    uri: uri ?? Uri.parse('wss://test.example.com'),
    transportMode: transportMode,
    enableHeartbeat: enableHeartbeat,
    autoConnect: autoConnect,
    reconnectPolicy: reconnectPolicy ?? const PDReconnectPolicy(maxAttempts: 3),
    messageQueueConfig: messageQueueConfig ?? const PDMessageQueueConfig(),
    heartbeatConfig: heartbeatConfig ?? const PDHeartbeatConfig(),
  );
  return PDLongLinkClient(config: config);
}

void main() {
  // ===== PDLongLinkConfig =====

  group('PDLongLinkConfig', () {
    test('default values', () {
      final config = PDLongLinkConfig(
        uri: Uri.parse('wss://example.com'),
      );

      expect(config.transportMode, PDLongLinkTransportMode.auto);
      expect(config.connectTimeout, const Duration(seconds: 10));
      expect(config.reconnectPolicy.maxAttempts, 10);
      expect(config.reconnectPolicy.baseDelay, const Duration(seconds: 1));
      expect(config.reconnectPolicy.maxDelay, const Duration(seconds: 30));
      expect(config.heartbeatConfig.interval, const Duration(seconds: 30));
      expect(config.heartbeatConfig.timeout, const Duration(seconds: 10));
      expect(config.heartbeatConfig.pingMessage, 'ping');
      expect(config.heartbeatConfig.pongMessage, 'pong');
      expect(config.autoConnect, false);
      expect(config.enableHeartbeat, true);
      expect(config.logger, isNull);
      expect(config.messageQueueConfig.enabled, false);
      expect(config.messageQueueConfig.maxSize, 100);
    });

    test('custom values', () {
      final logger = PDLogger(enableLogging: true);
      final config = PDLongLinkConfig(
        uri: Uri.parse('wss://test.com'),
        transportMode: PDLongLinkTransportMode.sse,
        connectTimeout: const Duration(seconds: 5),
        autoConnect: true,
        enableHeartbeat: false,
        logger: logger,
        messageQueueConfig: const PDMessageQueueConfig(
          enabled: true,
          maxSize: 50,
          overflowStrategy: PDMessageQueueOverflowStrategy.dropNewest,
        ),
      );

      expect(config.uri.toString(), 'wss://test.com');
      expect(config.transportMode, PDLongLinkTransportMode.sse);
      expect(config.connectTimeout, const Duration(seconds: 5));
      expect(config.autoConnect, true);
      expect(config.enableHeartbeat, false);
      expect(config.logger, logger);
      expect(config.messageQueueConfig.enabled, true);
      expect(config.messageQueueConfig.maxSize, 50);
      expect(config.messageQueueConfig.overflowStrategy, PDMessageQueueOverflowStrategy.dropNewest);
    });
  });

  // ===== PDReconnectPolicy =====

  group('PDReconnectPolicy', () {
    test('getDelay with jitter=0', () {
      const policy = PDReconnectPolicy(
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 30),
        jitterRatio: 0,
      );

      expect(policy.getDelay(0).inMilliseconds, 1000);
      expect(policy.getDelay(1).inMilliseconds, 2000);
      expect(policy.getDelay(2).inMilliseconds, 4000);
      expect(policy.getDelay(3).inMilliseconds, 8000);
      expect(policy.getDelay(4).inMilliseconds, 16000);
      expect(policy.getDelay(5).inMilliseconds, 30000);
      expect(policy.getDelay(6).inMilliseconds, 30000);
    });

    test('getDelay with jitter', () {
      const policy = PDReconnectPolicy(
        baseDelay: Duration(seconds: 10),
        maxDelay: Duration(seconds: 30),
        jitterRatio: 0.1,
      );

      final delay = policy.getDelay(0);
      expect(delay.inMilliseconds, greaterThanOrEqualTo(9000));
      expect(delay.inMilliseconds, lessThanOrEqualTo(11000));
    });

    test('getDelay clamps to maxDelay', () {
      const policy = PDReconnectPolicy(
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 5),
        jitterRatio: 0,
      );

      expect(policy.getDelay(10).inMilliseconds, 5000);
    });
  });

  // ===== PDLongLinkEvent =====

  group('PDLongLinkEvent', () {
    test('toString with short text', () {
      const event = PDLongLinkEvent(
        type: PDLongLinkEventType.message,
        text: 'Hello World',
      );
      expect(event.toString(), contains('PDLongLinkEvent'));
      expect(event.toString(), contains('message'));
      expect(event.toString(), contains('Hello World'));
      expect(event.toString(), isNot(contains('...')));
    });

    test('toString with long text', () {
      final longText = 'a' * 100;
      final event = PDLongLinkEvent(
        type: PDLongLinkEventType.message,
        text: longText,
      );
      expect(event.toString(), contains('...'));
      expect(event.toString().length, lessThan(200));
    });

    test('toString with error and closeCode', () {
      const event = PDLongLinkEvent(
        type: PDLongLinkEventType.close,
        closeCode: 1000,
        closeReason: 'Normal closure',
      );
      expect(event.toString(), contains('close'));
      expect(event.toString(), contains('1000'));
    });

    test('toString with null text', () {
      const event = PDLongLinkEvent(
        type: PDLongLinkEventType.open,
      );
      expect(event.toString(), contains('PDLongLinkEvent'));
      expect(event.toString(), contains('open'));
    });

    test('errorCode field', () {
      const event = PDLongLinkEvent(
        type: PDLongLinkEventType.error,
        error: 'test error',
        errorCode: PDLongLinkErrorCode.connectionTimeout,
      );
      expect(event.errorCode, PDLongLinkErrorCode.connectionTimeout);
      expect(event.toString(), contains('connectionTimeout'));
    });
  });

  // ===== PDLogger =====

  group('PDLogger', () {
    test('default values', () {
      final logger = PDLogger();
      expect(logger.enableLogging, true);
      expect(logger.logLevel, PDLogLevel.warning);
    });

    test('log level filtering', () {
      final logger = PDLogger(
        enableLogging: true,
        logLevel: PDLogLevel.error,
      );

      expect(logger.enableLogging, true);
      expect(logger.logLevel, PDLogLevel.error);
    });

    test('log callback captures all levels', () {
      final capturedData = <PDLogData>[];
      final logger = PDLogger(
        enableLogging: true,
        logLevel: PDLogLevel.debug,
        logCallback: (data) {
          capturedData.add(data);
        },
      );

      logger.logDebug('Test', 'Debug msg');
      logger.logInfo('Test', 'Info msg');
      logger.logWarning('Test', 'Warning msg');
      logger.logError('Test', 'Error msg');

      expect(capturedData.length, 4);
      expect(capturedData[0].level, PDLogLevel.debug);
      expect(capturedData[1].level, PDLogLevel.info);
      expect(capturedData[2].level, PDLogLevel.warning);
      expect(capturedData[3].level, PDLogLevel.error);
    });

    test('log info level filters debug', () {
      final capturedData = <PDLogData>[];
      final logger = PDLogger(
        enableLogging: true,
        logLevel: PDLogLevel.info,
        logCallback: (data) {
          capturedData.add(data);
        },
      );

      logger.logDebug('Test', 'Debug msg');
      logger.logInfo('Test', 'Info msg');
      logger.logWarning('Test', 'Warning msg');
      logger.logError('Test', 'Error msg');

      expect(capturedData.length, 3);
      expect(capturedData.any((d) => d.level == PDLogLevel.debug), isFalse);
    });

    test('log warning level filters info and debug', () {
      final capturedData = <PDLogData>[];
      final logger = PDLogger(
        enableLogging: true,
        logLevel: PDLogLevel.warning,
        logCallback: (data) {
          capturedData.add(data);
        },
      );

      logger.logDebug('Test', 'Debug msg');
      logger.logInfo('Test', 'Info msg');
      logger.logWarning('Test', 'Warning msg');
      logger.logError('Test', 'Error msg');

      expect(capturedData.length, 2);
      expect(capturedData.any((d) => d.level == PDLogLevel.debug), isFalse);
      expect(capturedData.any((d) => d.level == PDLogLevel.info), isFalse);
    });

    test('disabled logging', () {
      final logger = PDLogger(enableLogging: false);
      expect(() => logger.logDebug('Test', 'Debug'), returnsNormally);
      expect(() => logger.logInfo('Test', 'Info'), returnsNormally);
    });

    test('logInfo method exists and works', () {
      PDLogData? capturedData;
      final logger = PDLogger(
        enableLogging: true,
        logLevel: PDLogLevel.info,
        logCallback: (data) {
          capturedData = data;
        },
      );

      logger.logInfo('Test', 'Info message');
      expect(capturedData?.module, 'Test');
      expect(capturedData?.message, 'Info message');
      expect(capturedData?.level, PDLogLevel.info);
    });
  });

  // ===== PDHeartbeatConfig =====

  group('PDHeartbeatConfig', () {
    test('default values', () {
      const config = PDHeartbeatConfig();
      expect(config.interval, const Duration(seconds: 30));
      expect(config.timeout, const Duration(seconds: 10));
      expect(config.pingMessage, 'ping');
      expect(config.pongMessage, 'pong');
    });

    test('custom values', () {
      const config = PDHeartbeatConfig(
        interval: Duration(seconds: 15),
        timeout: Duration(seconds: 5),
        pingMessage: 'custom_ping',
        pongMessage: 'custom_pong',
      );
      expect(config.interval, const Duration(seconds: 15));
      expect(config.timeout, const Duration(seconds: 5));
      expect(config.pingMessage, 'custom_ping');
      expect(config.pongMessage, 'custom_pong');
    });
  });

  // ===== PDSseConfig =====

  group('PDSseConfig', () {
    test('default values', () {
      const config = PDSseConfig();
      expect(config.method, 'GET');
      expect(config.body, isNull);
      expect(config.eventTypes, isNull);
      expect(config.parseSseFormat, true);
      expect(config.lastEventId, isNull);
      expect(config.retryDelay, isNull);
    });

    test('custom values', () {
      const config = PDSseConfig(
        method: 'POST',
        body: {'key': 'value'},
        eventTypes: ['message', 'notification'],
        lastEventId: '123',
        parseSseFormat: false,
      );
      expect(config.method, 'POST');
      expect(config.body, {'key': 'value'});
      expect(config.eventTypes, ['message', 'notification']);
      expect(config.lastEventId, '123');
      expect(config.parseSseFormat, false);
    });
  });

  // ===== PDLongLinkErrorCode =====

  group('PDLongLinkErrorCode', () {
    test('all error codes exist', () {
      expect(PDLongLinkErrorCode.values.length, 10);
      expect(PDLongLinkErrorCode.unknown.index, 0);
      expect(PDLongLinkErrorCode.connectionTimeout.index, 1);
      expect(PDLongLinkErrorCode.heartbeatTimeout.index, 5);
      expect(PDLongLinkErrorCode.maxReconnectAttemptsReached.index, 9);
    });
  });

  // ===== PDMessageQueueConfig =====

  group('PDMessageQueueConfig', () {
    test('default values', () {
      const config = PDMessageQueueConfig();
      expect(config.enabled, false);
      expect(config.maxSize, 100);
      expect(config.overflowStrategy, PDMessageQueueOverflowStrategy.dropOldest);
    });

    test('custom values', () {
      const config = PDMessageQueueConfig(
        enabled: true,
        maxSize: 50,
        overflowStrategy: PDMessageQueueOverflowStrategy.dropNewest,
      );
      expect(config.enabled, true);
      expect(config.maxSize, 50);
      expect(config.overflowStrategy, PDMessageQueueOverflowStrategy.dropNewest);
    });
  });

  // ===== PDLogData =====

  group('PDLogData', () {
    test('toString with info level', () {
      final logData = PDLogData(
        timestamp: DateTime(2024, 1, 1, 12, 0, 0),
        level: PDLogLevel.info,
        module: 'Test',
        message: 'Test message',
      );
      expect(logData.toString(), contains('[INFO]'));
      expect(logData.toString(), contains('[Test]'));
      expect(logData.toString(), contains('Test message'));
    });
  });

  // ===== PDLogLevel =====

  group('PDLogLevel', () {
    test('extension getName', () {
      expect(PDLogLevel.error.getName, 'ERROR');
      expect(PDLogLevel.warning.getName, 'WARNING');
      expect(PDLogLevel.info.getName, 'INFO');
      expect(PDLogLevel.debug.getName, 'DEBUG');
    });

    test('values order', () {
      expect(PDLogLevel.error.index, 0);
      expect(PDLogLevel.warning.index, 1);
      expect(PDLogLevel.info.index, 2);
      expect(PDLogLevel.debug.index, 3);
    });
  });

  // ===== PDLongLinkTransportException =====

  group('PDLongLinkTransportException', () {
    test('toString', () {
      const exception = PDLongLinkTransportException('Test error');
      expect(exception.toString(), contains('PDLongLinkTransportException'));
      expect(exception.toString(), contains('Test error'));
    });

    test('message and errorCode', () {
      const exception = PDLongLinkTransportException(
        'Connection failed',
        errorCode: PDLongLinkErrorCode.connectionTimeout,
      );
      expect(exception.message, 'Connection failed');
      expect(exception.errorCode, PDLongLinkErrorCode.connectionTimeout);
    });
  });

  // ===== PDLongLinkState =====

  group('PDLongLinkState', () {
    test('values', () {
      expect(PDLongLinkState.disconnected.index, 0);
      expect(PDLongLinkState.connecting.index, 1);
      expect(PDLongLinkState.connected.index, 2);
      expect(PDLongLinkState.reconnecting.index, 3);
      expect(PDLongLinkState.failed.index, 4);
    });
  });

  // ===== PDLongLinkEventType =====

  group('PDLongLinkEventType', () {
    test('values', () {
      expect(PDLongLinkEventType.open.index, 0);
      expect(PDLongLinkEventType.close.index, 1);
      expect(PDLongLinkEventType.message.index, 2);
      expect(PDLongLinkEventType.error.index, 3);
      expect(PDLongLinkEventType.ping.index, 4);
      expect(PDLongLinkEventType.pong.index, 5);
    });
  });

  // ===== PDLongLinkTransportMode =====

  group('PDLongLinkTransportMode', () {
    test('values', () {
      expect(PDLongLinkTransportMode.auto.index, 0);
      expect(PDLongLinkTransportMode.io.index, 1);
      expect(PDLongLinkTransportMode.system.index, 2);
      expect(PDLongLinkTransportMode.sse.index, 3);
    });
  });

  // ===== MockTransport =====

  group('MockTransport', () {
    test('isConnected state management', () {
      final transport = MockTransport();
      expect(transport.isConnected, false);

      transport.simulateOpen();
      expect(transport.isConnected, true);

      transport.simulateClose();
      expect(transport.isConnected, false);
    });

    test('sendText when connected', () async {
      final transport = MockTransport();
      transport.simulateOpen();
      await transport.sendText('hello');
      expect(transport.sentTexts, ['hello']);
    });

    test('sendText throws when disconnected', () {
      final transport = MockTransport();
      expect(() => transport.sendText('hello'), throwsA(isA<PDLongLinkTransportException>()));
    });

    test('lastEventId setter', () {
      final transport = MockTransport();
      expect(transport.lastEventId, isNull);
      transport.lastEventId = 'evt123';
      expect(transport.lastEventId, 'evt123');
    });
  });

  // ===== PDMessageQueueOverflowStrategy =====

  group('PDMessageQueueOverflowStrategy', () {
    test('enum values exist', () {
      expect(PDMessageQueueOverflowStrategy.values.length, 2);
      expect(PDMessageQueueOverflowStrategy.dropOldest.index, 0);
      expect(PDMessageQueueOverflowStrategy.dropNewest.index, 1);
    });

    test('enum names', () {
      expect(PDMessageQueueOverflowStrategy.dropOldest.name, 'dropOldest');
      expect(PDMessageQueueOverflowStrategy.dropNewest.name, 'dropNewest');
    });
  });

  // ===== PDLongLinkEvent - binary =====

  group('PDLongLinkEvent binary', () {
    test('binary field', () {
      final bytes = [1, 2, 3, 4, 5];
      final event = PDLongLinkEvent(
        type: PDLongLinkEventType.message,
        binary: bytes,
      );
      expect(event.binary, bytes);
      expect(event.text, isNull);
    });

    test('toString with binary data', () {
      final bytes = List<int>.generate(100, (i) => i);
      final event = PDLongLinkEvent(
        type: PDLongLinkEventType.message,
        binary: bytes,
      );
      expect(event.toString(), contains('PDLongLinkEvent'));
      expect(event.toString(), contains('message'));
    });

    test('binary and text can coexist', () {
      const event = PDLongLinkEvent(
        type: PDLongLinkEventType.message,
        text: 'hello',
        binary: [1, 2, 3],
      );
      expect(event.text, 'hello');
      expect(event.binary, [1, 2, 3]);
    });
  });

  // ===== PDLongLinkEvent - close details =====

  group('PDLongLinkEvent close details', () {
    test('closeCode and closeReason fields', () {
      const event = PDLongLinkEvent(
        type: PDLongLinkEventType.close,
        closeCode: 1001,
        closeReason: 'Going away',
      );
      expect(event.closeCode, 1001);
      expect(event.closeReason, 'Going away');
    });

    test('closeCode null by default', () {
      const event = PDLongLinkEvent(
        type: PDLongLinkEventType.close,
      );
      expect(event.closeCode, isNull);
      expect(event.closeReason, isNull);
    });

    test('toString contains closeCode', () {
      const event = PDLongLinkEvent(
        type: PDLongLinkEventType.close,
        closeCode: 1006,
        closeReason: 'Abnormal closure',
      );
      expect(event.toString(), contains('1006'));
    });
  });

  // ===== PDLogger - error and stackTrace =====

  group('PDLogger error and stackTrace', () {
    test('logError with error and stackTrace', () {
      PDLogData? capturedData;
      final logger = PDLogger(
        enableLogging: true,
        logLevel: PDLogLevel.error,
        logCallback: (data) {
          capturedData = data;
        },
      );

      final testError = StateError('test error');
      final testStackTrace = StackTrace.current;
      logger.logError('Test', 'Error message', error: testError, stackTrace: testStackTrace);

      expect(capturedData, isNotNull);
      expect(capturedData?.error, testError);
      expect(capturedData?.stackTrace, testStackTrace);
      expect(capturedData?.level, PDLogLevel.error);
    });

    test('logError with only error', () {
      PDLogData? capturedData;
      final logger = PDLogger(
        enableLogging: true,
        logLevel: PDLogLevel.error,
        logCallback: (data) {
          capturedData = data;
        },
      );

      final testError = ArgumentError('invalid');
      logger.logError('Test', 'Error message', error: testError);

      expect(capturedData?.error, testError);
      expect(capturedData?.stackTrace, isNull);
    });

    test('logWarning with error and stackTrace', () {
      PDLogData? capturedData;
      final logger = PDLogger(
        enableLogging: true,
        logLevel: PDLogLevel.warning,
        logCallback: (data) {
          capturedData = data;
        },
      );

      final testError = RangeError('range');
      final testStackTrace = StackTrace.current;
      logger.logWarning('Test', 'Warning message', error: testError, stackTrace: testStackTrace);

      expect(capturedData?.error, testError);
      expect(capturedData?.stackTrace, testStackTrace);
      expect(capturedData?.level, PDLogLevel.warning);
    });
  });

  // ===== PDLogger - callback exception resilience =====

  group('PDLogger callback exception', () {
    test('logCallback throws does not crash logger', () {
      final logger = PDLogger(
        enableLogging: true,
        logLevel: PDLogLevel.debug,
        logCallback: (data) {
          throw Exception('callback error');
        },
      );

      expect(() => logger.logDebug('Test', 'debug msg'), returnsNormally);
      expect(() => logger.logInfo('Test', 'info msg'), returnsNormally);
      expect(() => logger.logWarning('Test', 'warning msg'), returnsNormally);
      expect(() => logger.logError('Test', 'error msg'), returnsNormally);
    });

    test('logCallback with error throws does not crash', () {
      final logger = PDLogger(
        enableLogging: true,
        logLevel: PDLogLevel.error,
        logCallback: (data) {
          throw StateError('boom');
        },
      );

      expect(
        () => logger.logError('Test', 'msg', error: ArgumentError('orig')),
        returnsNormally,
      );
    });
  });

  // ===== PDReconnectPolicy - boundary values =====

  group('PDReconnectPolicy boundary', () {
    test('getDelay with attempt=0', () {
      const policy = PDReconnectPolicy(
        baseDelay: Duration(seconds: 2),
        maxDelay: Duration(seconds: 30),
        jitterRatio: 0,
      );
      expect(policy.getDelay(0).inMilliseconds, 2000);
    });

    test('getDelay with large attempt clamps to maxDelay', () {
      const policy = PDReconnectPolicy(
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 30),
        jitterRatio: 0,
      );
      expect(policy.getDelay(5).inMilliseconds, 30000);
      expect(policy.getDelay(10).inMilliseconds, 30000);
      expect(policy.getDelay(20).inMilliseconds, 30000);
    });

    test('getDelay with large attempt but small maxDelay', () {
      const policy = PDReconnectPolicy(
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 5),
        jitterRatio: 0,
      );
      expect(policy.getDelay(3).inMilliseconds, 5000);
      expect(policy.getDelay(10).inMilliseconds, 5000);
    });

    test('getDelay with zero baseDelay and jitter', () {
      const policy = PDReconnectPolicy(
        baseDelay: Duration(seconds: 0),
        maxDelay: Duration(seconds: 10),
        jitterRatio: 0,
      );
      expect(policy.getDelay(0).inMilliseconds, 0);
      expect(policy.getDelay(5).inMilliseconds, 0);
    });
  });

  // ===== MockTransport - more methods =====

  group('MockTransport more methods', () {
    test('sendBinary when connected', () async {
      final transport = MockTransport();
      transport.simulateOpen();
      final bytes = [1, 2, 3];
      await transport.sendBinary(bytes);
      expect(transport.sentBinaries.length, 1);
      expect(transport.sentBinaries.first, [1, 2, 3]);
    });

    test('sendBinary throws when disconnected', () {
      final transport = MockTransport();
      expect(
        () => transport.sendBinary([1, 2, 3]),
        throwsA(isA<PDLongLinkTransportException>()),
      );
    });

    test('disconnect call count', () async {
      final transport = MockTransport();
      expect(transport.disconnectCallCount, 0);

      await transport.disconnect();
      expect(transport.disconnectCallCount, 1);

      await transport.disconnect(closeCode: 1000, closeReason: 'bye');
      expect(transport.disconnectCallCount, 2);
    });

    test('simulateError adds error event', () {
      final transport = MockTransport();
      final error = StateError('test error');

      expectLater(
        transport.events,
        emitsInOrder([
          isA<PDLongLinkEvent>().having(
            (e) => e.type,
            'type',
            PDLongLinkEventType.error,
          ),
        ]),
      );

      transport.simulateError(error);
    });

    test('simulateMessage adds message event', () {
      final transport = MockTransport();

      expectLater(
        transport.events,
        emitsInOrder([
          isA<PDLongLinkEvent>().having(
            (e) => e.type,
            'type',
            PDLongLinkEventType.message,
          ).having(
            (e) => e.text,
            'text',
            'hello world',
          ),
        ]),
      );

      transport.simulateMessage('hello world');
    });

    test('simulateBinaryMessage adds binary message event', () {
      final transport = MockTransport();
      final bytes = [10, 20, 30];

      expectLater(
        transport.events,
        emitsInOrder([
          isA<PDLongLinkEvent>().having(
            (e) => e.type,
            'type',
            PDLongLinkEventType.message,
          ).having(
            (e) => e.binary,
            'binary',
            bytes,
          ),
        ]),
      );

      transport.simulateBinaryMessage(bytes);
    });

    test('simulateOpen adds open event', () {
      final transport = MockTransport();

      expectLater(
        transport.events,
        emitsInOrder([
          isA<PDLongLinkEvent>().having(
            (e) => e.type,
            'type',
            PDLongLinkEventType.open,
          ),
        ]),
      );

      transport.simulateOpen();
    });

    test('simulateClose adds close event with code and reason', () {
      final transport = MockTransport();

      expectLater(
        transport.events,
        emitsInOrder([
          isA<PDLongLinkEvent>().having(
            (e) => e.type,
            'type',
            PDLongLinkEventType.close,
          ).having(
            (e) => e.closeCode,
            'closeCode',
            1001,
          ).having(
            (e) => e.closeReason,
            'closeReason',
            'Going away',
          ),
        ]),
      );

      transport.simulateClose(closeCode: 1001, closeReason: 'Going away');
    });

    test('multiple events in order', () {
      final transport = MockTransport();

      expectLater(
        transport.events,
        emitsInOrder([
          isA<PDLongLinkEvent>().having((e) => e.type, 'type', PDLongLinkEventType.open),
          isA<PDLongLinkEvent>().having((e) => e.type, 'type', PDLongLinkEventType.message),
          isA<PDLongLinkEvent>().having((e) => e.type, 'type', PDLongLinkEventType.error),
          isA<PDLongLinkEvent>().having((e) => e.type, 'type', PDLongLinkEventType.close),
        ]),
      );

      transport.simulateOpen();
      transport.simulateMessage('hi');
      transport.simulateError('oops');
      transport.simulateClose();
    });
  });

  // ===== PDSseConfig - retryDelay =====

  group('PDSseConfig retryDelay', () {
    test('retryDelay defaults to null', () {
      const config = PDSseConfig();
      expect(config.retryDelay, isNull);
    });

    test('custom retryDelay', () {
      const config = PDSseConfig(
        retryDelay: Duration(seconds: 5),
      );
      expect(config.retryDelay, const Duration(seconds: 5));
    });

    test('retryDelay with other custom values', () {
      const config = PDSseConfig(
        method: 'POST',
        retryDelay: Duration(milliseconds: 3000),
        parseSseFormat: false,
      );
      expect(config.method, 'POST');
      expect(config.retryDelay, const Duration(milliseconds: 3000));
      expect(config.parseSseFormat, false);
    });
  });

  // ===== PDLongLinkErrorCode - enum names =====

  group('PDLongLinkErrorCode names', () {
    test('enum value names', () {
      expect(PDLongLinkErrorCode.unknown.name, 'unknown');
      expect(PDLongLinkErrorCode.connectionTimeout.name, 'connectionTimeout');
      expect(PDLongLinkErrorCode.authenticationFailed.name, 'authenticationFailed');
      expect(PDLongLinkErrorCode.networkUnavailable.name, 'networkUnavailable');
      expect(PDLongLinkErrorCode.protocolError.name, 'protocolError');
      expect(PDLongLinkErrorCode.heartbeatTimeout.name, 'heartbeatTimeout');
      expect(PDLongLinkErrorCode.connectionClosed.name, 'connectionClosed');
      expect(PDLongLinkErrorCode.sendFailed.name, 'sendFailed');
      expect(PDLongLinkErrorCode.clientDisposed.name, 'clientDisposed');
      expect(PDLongLinkErrorCode.maxReconnectAttemptsReached.name, 'maxReconnectAttemptsReached');
    });

    test('all values are unique', () {
      final names = PDLongLinkErrorCode.values.map((e) => e.name).toSet();
      expect(names.length, PDLongLinkErrorCode.values.length);
    });

    test('values count is 10', () {
      expect(PDLongLinkErrorCode.values.length, 10);
    });
  });
}
