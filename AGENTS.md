# AGENTS.md - Flutter/Dart 项目开发规范

> 本文件为智能体（AI Agent）提供项目上下文、操作规范和编码准则。所有修改必须符合 Flutter 与 Dart 官方规范。

---

## 一、项目信息

### 当前项目

- **包名**: `pd_longlink`
- **类型**: Flutter 插件（Plugin）
- **仓库路径**: `/Users/pedro/LocalResources/pedro_working_space/pd_longlink`
- **主要功能**: WebSocket / SSE 长连接、心跳保活、自动重连、消息队列、日志系统
- **支持平台**: iOS、Android、Web、macOS、Windows、Linux
- **当前版本**: `1.0.0`

### 目录结构

```
pd_longlink/
├── lib/                          # 插件 Dart 代码
│   ├── pd_longlink.dart          # 公开导出入口
│   └── src/                      # 内部实现
│       ├── *.dart                # Dart 源文件
│       └── transport/            # 传输层实现
├── android/                      # Android 原生代码 (Kotlin)
├── ios/                          # iOS 原生代码 (Swift)
├── example/                      # 示例应用
│   └── lib/
│       ├── main.dart
│       ├── web_socket_demo.dart
│       └── sse_demo.dart
├── test/                         # 单元测试
├── .fvmrc                        # FVM 版本锁定
├── pubspec.yaml                  # 包配置
└── analysis_options.yaml         # 静态分析规则
```

---

## 二、FVM 版本管理（🔴 强制）

本项目使用 **FVM (Flutter Version Manager)** 锁定 Flutter 和 Dart SDK 版本。

### 当前版本

| 工具 | 版本 |
|------|------|
| Flutter | `3.10.6` |
| Dart SDK | 随 Flutter 锁定 |

### 命令前缀规则

**所有 `flutter` 和 `dart` 命令必须加 `fvm` 前缀。** 禁止直接调用裸命令。

| ❌ 禁止 | ✅ 正确 |
|---------|---------|
| `flutter pub get` | `fvm flutter pub get` |
| `flutter analyze` | `fvm flutter analyze` |
| `flutter test` | `fvm flutter test` |
| `flutter run` | `fvm flutter run` |
| `dart format .` | `fvm dart format .` |
| `dart analyze` | `fvm dart analyze` |

### 执行位置

- **插件根目录**: `/Users/pedro/LocalResources/pedro_working_space/pd_longlink`
- **示例程序**: `/Users/pedro/LocalResources/pedro_working_space/pd_longlink/example`

### 常用命令

```bash
# 安装依赖
fvm flutter pub get

# 静态分析（零 error、零 warning 才能提交）
fvm flutter analyze

# 运行测试
fvm flutter test

# 格式化
fvm dart format .

# 生成文档
fvm dart doc

# 发布预检查
fvm dart pub publish --dry-run
```

### IDE SDK 修复

若 IDE 提示使用了不存在于当前 SDK 版本的 API：

1. 确认 `.fvm/flutter_sdk` 软链接指向 `/Users/pedro/fvm/versions/3.10.6`
2. 删除被污染的 `.dart_tool/` 目录
3. 执行 `fvm flutter pub get` 重新解析
4. 重载 IDE 窗口

---

## 三、Dart 编码规范

遵循 [Effective Dart](https://dart.dev/effective-dart) 官方规范，以 `analysis_options.yaml` 中配置的 `flutter_lints` 为底线。

### 3.1 命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| 类 / 枚举 / typedef / 类型参数 | `PascalCase` | `PDLongLinkClient`, `PDLogLevel` |
| 库 / 包 / 目录 / 源文件 | `snake_case` | `pd_long_link_client.dart` |
| 变量 / 常量 / 参数 / 命名参数 | `camelCase` | `connectTimeout`, `baseDelay` |
| 库前缀（import） | `snake_case` + 下划线 | `import 'dart:io' as io;` |
| 私有成员 | `camelCase` 前缀 `_` | `_transport`, `_logger` |
| 枚举值 | `camelCase` | `disconnected`, `heartbeatTimeout` |
| 常量（static const / 顶级 final）| `camelCase` | `defaultTimeout` |

### 3.2 导入规范

- 使用 `package:` 导入外部包和本项目代码
- 使用 `dart:` 导入标准库
- 使用相对路径 `../` 导入同一包内其他文件
- **禁止** 裸导入（如 `import 'a.dart';` 与 `import 'package:foo/a.dart';` 混用）
- 清理未使用的导入

```dart
// ✅ 正确
import 'dart:async';
import 'package:flutter/material.dart';
import '../pd_long_link_core.dart';

// ❌ 错误
import '../../../../../lib/src/transport/pd_sse_transport.dart';
```

### 3.3 类型注解

- 优先使用 `var` / `final` 让类型推断，除非需要明确接口类型
- 公共 API 的返回类型和参数类型必须显式注解
- 避免使用 `dynamic`，除非确实需要

```dart
// ✅ 正确
final client = PDLongLinkClient(config: config);
Stream<PDLongLinkEvent> get events => _events.stream;

// ❌ 错误
var x;  // 未推断类型
Stream get events => _events.stream;  // 缺少泛型
```

### 3.4 构造函数

- 优先使用 `const` 构造函数（当类字段均为 final 且类型支持 const 时）
- 命名参数使用 `{required this.field}` 形式
- 私有构造函数使用 `_` 前缀

```dart
// ✅ 正确
class PDHeartbeatConfig {
  final Duration interval;
  const PDHeartbeatConfig({this.interval = const Duration(seconds: 30)});
}

// ❌ 错误
class Foo {
  late int value;  // 不必要的 late
  Foo(int v) { value = v; }
}
```

### 3.5 异步编程

- 优先使用 `async` / `await`，避免 `.then()` 链式调用
- 有返回值的方法必须显式返回 `Future<T>`
- 取消异步操作时使用 `CancelableOperation` 或手动管理 `StreamSubscription`

```dart
// ✅ 正确
Future<void> connect() async {
  await _transport!.connect(...);
}

// ❌ 错误
void connect() {  // 缺少 Future 返回类型
  _transport!.connect(...).then((_) { ... });
}
```

### 3.6 错误处理

- 使用自定义异常替代裸 `throw String`
- 异常消息使用中文（与用户交互语言一致）
- 异常构造时附带 `StackTrace` 和错误码（如有）

```dart
// ✅ 正确
throw const PDLongLinkTransportException('连接失败', errorCode: PDLongLinkErrorCode.connectionTimeout);

// ❌ 错误
throw '连接失败';  // 裸字符串异常
```

### 3.7 集合字面量

- 优先使用字面量而非构造函数
- 使用 `const` 集合当内容不变时

```dart
// ✅ 正确
const emptyList = <String>[];
final map = {'key': 'value'};

// ❌ 错误
final list = List<String>();  // 废弃构造函数
final map = Map<String, String>();  // 应使用字面量
```

### 3.8 字符串与插值

- 优先使用单引号 `'`，除非字符串包含单引号
- 简单插值省略 `{}`，复杂表达式保留

```dart
// ✅ 正确
final msg = '连接成功: $uri';
final detail = '延迟: ${latency.inMilliseconds}ms';

// ❌ 错误
final msg = "连接成功";  // 双引号（无特殊字符时）
final detail = '延迟: ${latency}';  // 不必要的括号
```

---

## 四、Flutter 编码规范

### 4.1 Widget 构建

- 构建方法保持纯净（无副作用、无状态变更）
- 使用 `const` 构造函数减少重建开销
- 拆分复杂 UI 为独立方法或 StatelessWidget
- 使用 `Key` 区分有状态列表项

```dart
// ✅ 正确
@override
Widget build(BuildContext context) {
  return Column(
    children: [
      const Header(),  // const
      _buildBody(),    // 提取方法
    ],
  );
}

// ❌ 错误
@override
Widget build(BuildContext context) {
  _fetchData();  // 副作用！
  return Container(...);  // 无 const
}
```

### 4.2 状态管理

- 优先使用 `StatefulWidget` 管理局部状态
- 避免在 `build()` 中调用 `setState()`
- dispose 时清理所有资源（Timer、Subscription、Controller）

```dart
@override
void dispose() {
  _timer?.cancel();
  _subscription?.cancel();
  _controller.dispose();
  super.dispose();
}
```

### 4.3 布局与滚动

- `Column` / `Row` 内容可能溢出时，使用 `SingleChildScrollView` 或 `Expanded` / `Flexible`
- 列表使用 `ListView.builder`（大量数据时）
- 避免嵌套可滚动组件导致手势冲突

```dart
// ✅ 正确
SingleChildScrollView(
  child: Column(
    children: [
      ...cards,
      SizedBox(
        height: 300,
        child: ListView.builder(...),
      ),
    ],
  ),
)

// ❌ 错误
Column(  // 内容过多会溢出
  children: [Card(...), Card(...), ListView(...)],
)
```

---

## 五、文档注释规范

### 5.1 dartdoc 要求

- 所有公开 API（public classes, methods, getters, setters）必须有 `///` 文档注释
- 文档注释第一行是简短摘要（一句话）
- 参数用 `[paramName]` 标注
- 使用代码示例说明复杂用法

```dart
/// 建立与指定 URI 的长连接。
///
/// 连接成功后会触发 [PDLongLinkEventType.open] 事件。
/// 如果配置了 [PDLongLinkConfig.autoConnect] 为 `true`，
/// 构造函数中会自动调用此方法。
///
/// 示例：
/// ```dart
/// final client = PDLongLinkClient(config: config);
/// await client.connect();
/// ```
///
/// 如果连接失败，会进入自动重连逻辑（如配置启用）。
Future<void> connect() async { ... }
```

### 5.2 行内注释

- 使用 `//` 解释非显而易见的逻辑
- 注释应解释"为什么"而非"做什么"
- 复杂算法需分步注释

```dart
// ✅ 正确
// 使用 generation 计数器确保旧连接的事件不会干扰新连接
_generation++;

// ❌ 错误
// i 自增
i++;
```

---

## 六、测试规范

### 6.1 测试组织

- 使用 `group()` 按类或功能分组
- 测试名使用中文描述行为：`test('连接成功后状态变为 connected', () { ... })`
- 每个测试独立，不依赖执行顺序

### 6.2 测试覆盖要求

- 所有公开 API 必须有对应测试
- 边界值和异常情况必须覆盖
- Mock 外部依赖（网络、平台通道等）

```dart
group('PDLongLinkClient', () {
  test('连接成功后状态变为 connected', () async {
    final client = createTestClient();
    await client.connect();
    expect(client.currentState, PDLongLinkState.connected);
  });

  test('断开连接后状态变为 disconnected', () async {
    final client = createTestClient();
    await client.connect();
    await client.disconnect();
    expect(client.currentState, PDLongLinkState.disconnected);
  });
});
```

### 6.3 运行测试

```bash
fvm flutter test test/pd_longlink_test.dart
```

---

## 七、文件与目录规范

### 7.1 文件组织

- 每个文件只包含一个公开类（或紧密相关的多个小类）
- 文件名与主类名对应：`class PDLongLinkClient` → `pd_long_link_client.dart`
- 平台特定实现使用条件导入：

```dart
import 'transport/pd_sse_transport_stub.dart'
    if (dart.library.io) 'transport/pd_sse_transport.dart'
    if (dart.library.html) 'transport/pd_sse_transport_web.dart';
```

### 7.2 避免循环依赖

- 公共类型提取到独立文件（如 `pd_log_types.dart`）
- 核心接口定义在顶层，实现细节在子目录

---

## 八、版本与发布规范

### 8.1 语义化版本

遵循 [SemVer](https://semver.org/lang/zh-CN/)：`MAJOR.MINOR.PATCH`

| 版本变化 | 触发条件 |
|---------|---------|
| MAJOR +1 | 破坏性变更（Breaking Change） |
| MINOR +1 | 向后兼容的新功能 |
| PATCH +1 | 向后兼容的问题修复 |

### 8.2 发布检查清单

1. 更新 `pubspec.yaml` 版本号
2. 更新 `CHANGELOG.md`（英文）
  - 更新 `README_CN.md`（中文）非必须项
  - 更新 `README.md`（英文）非必须项
3. 运行 `fvm flutter analyze` — 必须零 error、零 warning
4. 运行 `fvm flutter test` — 必须全部通过
5. 运行 `fvm dart doc` — 文档无报错
6. `fvm dart pub publish --dry-run` — 预检查通过

---

## 九、日志与输出规范

### 9.1 语言要求

- **用户交互**: 中文（与用户消息语言一致）
- **代码注释**: 中文
- **日志输出**: 中文
- **异常消息**: 中文

### 9.2 日志级别使用

| 级别 | 使用场景 |
|------|---------|
| `debug` | 开发调试信息（连接详情、心跳发送等） |
| `info` | 重要业务事件（连接成功、断开、重连开始） |
| `warning` | 异常情况但不影响核心功能（重连失败但仍在尝试） |
| `error` | 严重错误（连接完全失败、心跳超时、发送失败） |

---

## 十、常见问题（FAQ）

### Q: IDE 提示使用了不存在于当前 SDK 版本的 API？

A: 检查 `.dart_tool/version` 是否显示 `3.10.6`。若显示其他版本：
1. 删除 `.dart_tool/` 目录
2. 执行 `fvm flutter pub get`
3. 重载 IDE

### Q: 分析时出现 `deprecated_member_use` 警告？

A: 如果警告来自当前 SDK 版本已弃用的 API，需替换为新 API。如果来自更高版本的 API，说明 `.dart_tool` 被错误版本污染，按上一条修复。

### Q: 跨平台代码如何处理？

A: 使用条件导入（`dart.library.io` / `dart.library.html`）+ stub 文件模式。详见 `lib/src/transport/` 目录实现。

---

## 参考文档

- [Dart 官方 Effective Dart](https://dart.dev/effective-dart)
- [Flutter 官方 Style Guide](https://github.com/flutter/flutter/blob/master/docs/contributing/Style-guide-for-Flutter-repo.md)
- [Flutter Lints 规则列表](https://pub.dev/packages/flutter_lints)
- [SemVer 语义化版本规范](https://semver.org/lang/zh-CN/)
- [FVM 官方文档](https://fvm.app/documentation)
- [PD LongLink README.md](./README.md)
- [PD LongLink README_CN.md](./README_CN.md)
- [PD LongLink CHANGELOG.md](./CHANGELOG.md)
