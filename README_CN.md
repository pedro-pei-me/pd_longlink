# PD LongLink

[中文](/README_CN.md) | [English](/README.md)

面向 Flutter 的生产级长连接库，支持 WebSocket、系统 WebSocket 和 Server-Sent Events (SSE)，具备自动重连、心跳检测和生命周期感知能力。

## 功能特性

- **多传输模式支持**：WebSocket（IO/系统）、SSE
- **自动重连**：带抖动的指数退避策略
- **心跳检测**：周期性 ping/pong 维持连接健康状态
- **生命周期感知**：自动响应应用前后台切换
- **跨平台**：iOS/Android/Web/macOS/Windows/Linux

## 安装

```yaml
dependencies:
  pd_longlink: ^1.0.0
```

## 快速开始

```dart
import 'package:pd_longlink/pd_longlink.dart';

void main() {
  final config = PDLongLinkConfig(
    uri: Uri.parse('wss://example.com/ws'),
    autoConnect: true,
  );

  final client = PDLongLinkClient(config: config);

  client.state.listen((state) {
    print('状态变化: $state');
  });

  client.events.listen((event) {
    switch (event.type) {
      case PDLongLinkEventType.message:
        print('收到消息: ${event.text}');
        break;
      case PDLongLinkEventType.error:
        print('错误: ${event.error}');
        break;
      default:
        break;
    }
  });
}
```

## API 参考

### 枚举类型

#### PDLongLinkState

| 值             | 说明                           |
| -------------- | ------------------------------ |
| `disconnected` | 连接已关闭                     |
| `connecting`   | 连接中                         |
| `connected`    | 连接已建立                     |
| `reconnecting` | 断开后重连中                   |
| `failed`       | 连接失败（已达到最大重连次数） |

#### PDLongLinkEventType

| 值        | 说明          |
| --------- | ------------- |
| `open`    | 连接打开      |
| `close`   | 连接关闭      |
| `message` | 收到消息      |
| `error`   | 发生错误      |
| `ping`    | 发送心跳 ping |
| `pong`    | 收到心跳 pong |

#### PDLongLinkTransportMode

| 值       | 说明                                       |
| -------- | ------------------------------------------ |
| `auto`   | 自动选择（移动端使用 system，Web 使用 io） |
| `io`     | Dart IO WebSocket                          |
| `system` | 系统原生 WebSocket（仅 Android/iOS）       |
| `sse`    | Server-Sent Events                         |

#### PDLogLevel

| 值        | 说明                          |
| --------- | ----------------------------- |
| `error`   | 仅错误日志                    |
| `warning` | 错误 + 警告日志（默认级别）   |
| `info`    | 错误 + 警告 + 信息日志        |
| `debug`   | 全部日志                      |

#### PDLongLinkErrorCode

| 值                              | 说明                       |
| ------------------------------- | -------------------------- |
| `unknown`                       | 未知错误                   |
| `connectionTimeout`             | 连接超时                   |
| `authenticationFailed`          | 认证失败                   |
| `networkUnavailable`            | 网络不可用                 |
| `protocolError`                 | 协议错误                   |
| `heartbeatTimeout`              | 心跳超时                   |
| `connectionClosed`              | 连接已关闭                 |
| `sendFailed`                    | 发送失败                   |
| `clientDisposed`                | 客户端已释放               |
| `maxReconnectAttemptsReached`   | 达到最大重连次数           |

#### PDMessageQueueOverflowStrategy

| 值            | 说明             |
| ------------- | ---------------- |
| `dropOldest`  | 丢弃最旧的消息   |
| `dropNewest`  | 丢弃最新的消息   |

### 配置类

#### PDLongLinkConfig

```dart
const PDLongLinkConfig({
  required this.uri,                    // 连接地址（必填）
  this.transportMode = PDLongLinkTransportMode.auto,
  this.headers,                         // 自定义请求头
  this.connectTimeout = const Duration(seconds: 10),
  this.reconnectPolicy = const PDReconnectPolicy(),
  this.heartbeatConfig = const PDHeartbeatConfig(),
  this.autoConnect = false,
  this.enableHeartbeat = true,
  this.sseConfig,                       // SSE 模式专用配置
  this.messageQueueConfig = const PDMessageQueueConfig(),  // 消息队列配置
  this.logger,                          // 自定义日志实例
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

**延迟计算公式**：`delay = baseDelay * 2^attempt ± jitter`

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
  this.enabled = false,                                                       // 是否启用消息队列
  this.maxSize = 100,                                                         // 队列最大容量
  this.overflowStrategy = PDMessageQueueOverflowStrategy.dropOldest,         // 溢出策略
});
```

### PDLongLinkClient

#### 构造函数

```dart
PDLongLinkClient({required PDLongLinkConfig config})
```

#### 属性

| 属性           | 类型                      | 说明                                 |
| -------------- | ------------------------- | ------------------------------------ |
| `state`        | `Stream<PDLongLinkState>` | 状态变化流                           |
| `events`       | `Stream<PDLongLinkEvent>` | 事件流                               |
| `currentState` | `PDLongLinkState`         | 当前连接状态                         |
| `lastEventId`  | `String?`                 | 上次事件 ID（SSE 模式下用于断点续传） |

#### 方法

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

`PDLogger` 为实例类，可通过 `PDLongLinkConfig.logger` 注入自定义实例，未提供时客户端会创建默认实例（日志级别为 `warning`）。

```dart
PDLogger({
  this.enableLogging = true,
  this.logLevel = PDLogLevel.warning,
  this.logCallback,
});
```

实例方法：

- `logDebug(String module, String message)`：记录调试级别日志
- `logInfo(String module, String message)`：记录信息级别日志
- `logWarning(String module, String message, {Object? error, StackTrace? stackTrace})`：记录警告级别日志
- `logError(String module, String message, {Object? error, StackTrace? stackTrace})`：记录错误级别日志

`PDLongLinkClient` 上提供以下日志代理方法，便于运行时动态调整日志行为：

- `setLogLevel(PDLogLevel level)`：设置日志级别
- `enableLogging(bool enable)`：启用或禁用日志
- `setLogCallback(PDLogCallback? callback)`：设置自定义日志回调

### PDLongLinkTransportException

```dart
const PDLongLinkTransportException(this.message, {this.errorCode});
```

## 平台行为

### Web 平台

- **WebSocket**：使用浏览器原生 `WebSocket` API
- **SSE**：使用浏览器原生 `EventSource` API
- **System WebSocket**：不支持，自动降级到 IO 模式
- **注意**：SSE 的 `retryDelay` 配置在 Web 上会被忽略，因为 `EventSource.retry` 是只读属性

### 移动平台（Android/iOS）

- **System WebSocket**：使用原生平台 WebSocket，后台行为更好
- **IO WebSocket**：使用 Dart 的 `dart:io` WebSocket
- **SSE**：使用 Dio HTTP 客户端的流式支持

## 传输模式对比

| 模式     | 平台支持    | 双向通信 | 后台保活 |
| -------- | ----------- | -------- | -------- |
| `io`     | 全平台      | ✅       | ❌       |
| `system` | Android/iOS | ✅       | ✅       |
| `sse`    | 全平台      | ❌       | ⚠️       |

## 完整示例

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
            _messages.add('收到: ${event.text}');
          });
          break;
        case PDLongLinkEventType.error:
          setState(() {
            _messages.add('错误: ${event.error}');
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
      await _client.sendText('来自 PD LongLink 的问候！');
      setState(() {
        _messages.add('发送: 来自 PD LongLink 的问候！');
      });
    } catch (e) {
      setState(() {
        _messages.add('发送失败: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PD LongLink 示例')),
      body: Column(
        children: [
          Text('状态: $_status'),
          Row(
            children: [
              ElevatedButton(
                onPressed: () => _client.connect(),
                child: const Text('连接'),
              ),
              ElevatedButton(
                onPressed: () => _client.disconnect(),
                child: const Text('断开'),
              ),
              ElevatedButton(
                onPressed: _sendMessage,
                child: const Text('发送'),
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

## 注意事项

1. **资源管理**：客户端不再使用时务必调用 `dispose()`
2. **SSE 限制**：SSE 模式仅支持接收消息，不支持发送
3. **System 模式**：仅在 Android/iOS 上可用，其他平台会降级到 IO 模式
4. **生命周期**：客户端会自动监听应用生命周期事件
5. **日志**：默认日志级别为 warning

## 许可证

MIT
