# PD LongLink

[中文](/README_CN.md) | [English](/README.md)

Production-grade long connection library for Flutter, supporting WebSocket, System WebSocket and Server-Sent Events (SSE) with auto-reconnect, heartbeat and lifecycle awareness.

## Features

- **Multi-transport Support**: WebSocket (IO/System), SSE
- **Auto Reconnect**: Exponential backoff strategy with jitter
- **Heartbeat Detection**: Periodic ping/pong to maintain connection health
- **Lifecycle Awareness**: Automatically respond to app foreground/background transitions
- **Cross-platform**: iOS/Android/Web/macOS/Windows/Linux

## Installation

```yaml
dependencies:
  pd_longlink: ^1.0.0
```

## Quick Start

```dart
import 'package:pd_longlink/pd_longlink.dart';

void main() {
  final config = PDLongLinkConfig(
    uri: Uri.parse('wss://example.com/ws'),
    autoConnect: true,
  );

  final client = PDLongLinkClient(config: config);

  client.state.listen((state) {
    print('State changed: $state');
  });

  client.events.listen((event) {
    switch (event.type) {
      case PDLongLinkEventType.message:
        print('Received message: ${event.text}');
        break;
      case PDLongLinkEventType.error:
        print('Error: ${event.error}');
        break;
      default:
        break;
    }
  });
}
```

## API Reference

### Enums

#### PDLongLinkState

| Value | Description |
|---|---|
| `disconnected` | Connection is closed |
| `connecting` | Connecting in progress |
| `connected` | Connection established |
| `reconnecting` | Reconnecting after disconnection |
| `failed` | Connection failed (max retry attempts reached) |

#### PDLongLinkEventType

| Value | Description |
|---|---|
| `open` | Connection opened |
| `close` | Connection closed |
| `message` | Message received |
| `error` | Error occurred |
| `ping` | Heartbeat ping sent |
| `pong` | Heartbeat pong received |

#### PDLongLinkTransportMode

| Value | Description |
|---|---|
| `auto` | Auto-select (system on mobile, io on web) |
| `io` | Dart IO WebSocket |
| `system` | Native system WebSocket (Android/iOS only) |
| `sse` | Server-Sent Events |

#### PDLogLevel

| Value | Description |
|---|---|
| `error` | Error only |
| `warning` | Error + Warning |
| `info` | Error + Warning + Info |
| `debug` | All logs |

#### PDLongLinkErrorCode

| Value | Description |
|---|---|
| `unknown` | Unknown error |
| `connectionTimeout` | Connection timed out |
| `authenticationFailed` | Authentication failed |
| `networkUnavailable` | Network unavailable |
| `protocolError` | Protocol error |
| `heartbeatTimeout` | Heartbeat timeout |
| `connectionClosed` | Connection closed |
| `sendFailed` | Send message failed |
| `clientDisposed` | Client has been disposed |
| `maxReconnectAttemptsReached` | Max reconnect attempts reached |

#### PDMessageQueueOverflowStrategy

| Value | Description |
|---|---|
| `dropOldest` | Drop the oldest message when queue is full |
| `dropNewest` | Drop the newest message when queue is full |

### Configuration

#### PDLongLinkConfig

```dart
const PDLongLinkConfig({
  required this.uri,                    // Connection URI (required)
  this.transportMode = PDLongLinkTransportMode.auto,
  this.headers,                         // Custom headers
  this.connectTimeout = const Duration(seconds: 10),
  this.reconnectPolicy = const PDReconnectPolicy(),
  this.heartbeatConfig = const PDHeartbeatConfig(),
  this.autoConnect = false,
  this.enableHeartbeat = true,
  this.sseConfig,                       // Required for SSE mode
  this.messageQueueConfig = const PDMessageQueueConfig(),
  this.logger,                          // Custom logger instance
});
```

#### PDReconnectPolicy

```dart
const PDReconnectPolicy({
  this.maxAttempts = 10,
  this.baseDelay = const Duration(seconds: 1),
  this.maxDelay = const Duration(seconds: 30),
  this.jitterRatio = 0.1,
  this.enableInBackground = true,
  this.reconnectOnResume = true,
  this.reconnectOnDisconnect = true,
});
```

**Delay Calculation**: `delay = baseDelay * 2^attempt ± jitter`

#### PDHeartbeatConfig

```dart
const PDHeartbeatConfig({
  this.interval = const Duration(seconds: 30),
  this.timeout = const Duration(seconds: 10),
  this.pingMessage = 'ping',
  this.pongMessage = 'pong',
});
```

#### PDSseConfig

```dart
const PDSseConfig({
  this.method = 'GET',
  this.body,
  this.eventTypes,
  this.parseSseFormat = true,
  this.lastEventId,
  this.retryDelay,
});
```

#### PDMessageQueueConfig

```dart
const PDMessageQueueConfig({
  this.enabled = false,
  this.maxSize = 100,
  this.overflowStrategy = PDMessageQueueOverflowStrategy.dropOldest,
});
```

### PDLongLinkClient

#### Constructor

```dart
PDLongLinkClient({required PDLongLinkConfig config})
```

#### Properties

| Property | Type | Description |
|---|---|---|
| `state` | `Stream<PDLongLinkState>` | State change stream |
| `events` | `Stream<PDLongLinkEvent>` | Event stream |
| `currentState` | `PDLongLinkState` | Current connection state |
| `lastEventId` | `String?` | Last event ID (for SSE resume) |

#### Methods

**connect()**
```dart
Future<void> connect()
```

**disconnect()**
```dart
Future<void> disconnect({int? closeCode, String? closeReason})
```

**sendText()**
```dart
Future<void> sendText(String text)
```

**sendBinary()**
```dart
Future<void> sendBinary(List<int> bytes)
```

**dispose()**
```dart
Future<void> dispose()
```

**setLogLevel()**
```dart
void setLogLevel(PDLogLevel level)
```

**enableLogging()**
```dart
void enableLogging(bool enable)
```

**setLogCallback()**
```dart
void setLogCallback(PDLogCallback? callback)
```

### PDLongLinkEvent

```dart
const PDLongLinkEvent({
  required this.type,
  this.text,
  this.binary,
  this.error,
  this.errorCode,
  this.closeCode,
  this.closeReason,
});
```

### PDLogger

```dart
PDLogger({
  this.enableLogging = true,
  this.logLevel = PDLogLevel.warning,
  this.logCallback,
});
```

**Instance Methods:**

- `logDebug(String module, String message)` — Log a debug-level message
- `logInfo(String module, String message)` — Log an info-level message
- `logWarning(String module, String message, {Object? error, StackTrace? stackTrace})` — Log a warning-level message
- `logError(String module, String message, {Object? error, StackTrace? stackTrace})` — Log an error-level message

**PDLongLinkClient Proxy Methods:**

The `PDLongLinkClient` provides convenience methods that delegate to its internal `PDLogger` instance:

- `setLogLevel(PDLogLevel level)` — Update the log level
- `enableLogging(bool enable)` — Enable or disable logging
- `setLogCallback(PDLogCallback? callback)` — Set a custom log callback

### PDLongLinkTransportException

```dart
const PDLongLinkTransportException(this.message, {this.errorCode});
```

## Platform Behavior

### Web Platform

- **WebSocket**: Uses browser's native `WebSocket` API
- **SSE**: Uses browser's native `EventSource` API
- **System WebSocket**: Not supported, automatically falls back to IO mode
- **Note**: SSE `retryDelay` configuration is ignored on Web as `EventSource.retry` is read-only

### Mobile Platforms (Android/iOS)

- **System WebSocket**: Uses native platform WebSocket with better background behavior
- **IO WebSocket**: Uses Dart's `dart:io` WebSocket
- **SSE**: Uses Dio HTTP client with streaming support

## Transport Mode Comparison

| Mode | Platform | Bidirectional | Background Keepalive |
|---|---|---|---|
| `io` | All | ✅ | ❌ |
| `system` | Android/iOS | ✅ | ✅ |
| `sse` | All | ❌ | ⚠️ |

## Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:pd_longlink/pd_longlink.dart';

class LongLinkDemo extends StatefulWidget {
  const LongLinkDemo({super.key});

  @override
  State<LongLinkDemo> createState() => _LongLinkDemoState();
}

class _LongLinkDemoState extends State<LongLinkDemo> {
  late PDLongLinkClient _client;
  String _status = 'Disconnected';
  List<String> _messages = [];

  @override
  void initState() {
    super.initState();

    final config = PDLongLinkConfig(
      uri: Uri.parse('wss://echo.websocket.org'),
      transportMode: PDLongLinkTransportMode.auto,
      reconnectPolicy: const PDReconnectPolicy(
        maxAttempts: 5,
        baseDelay: Duration(seconds: 2),
      ),
      heartbeatConfig: const PDHeartbeatConfig(
        interval: Duration(seconds: 20),
        timeout: Duration(seconds: 5),
      ),
      enableHeartbeat: true,
      autoConnect: false,
    );

    _client = PDLongLinkClient(config: config);

    _client.state.listen((state) {
      setState(() {
        _status = state.toString().split('.').last;
      });
    });

    _client.events.listen((event) {
      switch (event.type) {
        case PDLongLinkEventType.message:
          setState(() {
            _messages.add('Received: ${event.text}');
          });
          break;
        case PDLongLinkEventType.error:
          setState(() {
            _messages.add('Error: ${event.error}');
          });
          break;
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    try {
      await _client.sendText('Hello from PD LongLink!');
      setState(() {
        _messages.add('Sent: Hello from PD LongLink!');
      });
    } catch (e) {
      setState(() {
        _messages.add('Send failed: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PD LongLink Demo')),
      body: Column(
        children: [
          Text('Status: $_status'),
          Row(
            children: [
              ElevatedButton(
                onPressed: () => _client.connect(),
                child: const Text('Connect'),
              ),
              ElevatedButton(
                onPressed: () => _client.disconnect(),
                child: const Text('Disconnect'),
              ),
              ElevatedButton(
                onPressed: _sendMessage,
                child: const Text('Send'),
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) => Text(_messages[index]),
            ),
          ),
        ],
      ),
    );
  }
}
```

## Notes

1. **Resource Management**: Always call `dispose()` when the client is no longer needed
2. **SSE Limitation**: SSE mode only supports receiving messages, not sending
3. **System Mode**: Only available on Android/iOS, falls back to IO mode on other platforms
4. **Lifecycle**: Client automatically listens to App lifecycle events
5. **Logging**: Default log level is `warning`

## License

MIT