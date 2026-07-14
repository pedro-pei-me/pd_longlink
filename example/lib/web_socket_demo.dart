import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pd_longlink/pd_longlink.dart';

import 'main.dart';

class WebSocketDemoPage extends StatefulWidget {
  const WebSocketDemoPage({super.key});

  @override
  State<WebSocketDemoPage> createState() => _WebSocketDemoPageState();
}

class _WebSocketDemoPageState extends State<WebSocketDemoPage> {
  PDLongLinkClient? _client;
  PDLogger? _logger;
  StreamSubscription<PDLongLinkEvent>? _eventSubscription;
  StreamSubscription<PDLongLinkState>? _stateSubscription;
  final List<LogEntry> _logs = [];
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _pongMessageController = TextEditingController(text: 'pong');
  PDLongLinkState _currentState = PDLongLinkState.disconnected;
  bool _isConnecting = false;
  bool _loggingEnabled = true;
  PDLogLevel _currentLogLevel = PDLogLevel.debug;
  bool _messageQueueEnabled = false;
  final int _messageQueueMaxSize = 100;
  PDMessageQueueOverflowStrategy _messageQueueOverflowStrategy = PDMessageQueueOverflowStrategy.dropOldest;
  int _queueSize = 0;
  String _lastEventIdDisplay = 'N/A';

  @override
  void dispose() {
    debugPrint('[WebSocketDemo] dispose 开始');
    _eventSubscription?.cancel();
    _stateSubscription?.cancel();
    _client?.dispose();
    _messageController.dispose();
    _pongMessageController.dispose();
    debugPrint('[WebSocketDemo] dispose 完成');
    super.dispose();
  }

  void _appendLog(String message, [LogType type = LogType.info]) {
    debugPrint('[WebSocketDemo] [$type] $message');
    setState(() {
      _logs.insert(0, LogEntry(message, type));
      if (_logs.length > 100) {
        _logs.removeLast();
      }
    });
  }

  PDLogger _createCustomLogger() {
    return PDLogger(
      enableLogging: _loggingEnabled,
      logLevel: _currentLogLevel,
      logCallback: (logData) {
        _appendLog('[SDK] [${logData.level.getName}] ${logData.module}: ${logData.message}', LogType.debug);
      },
    );
  }

  Future<void> _connect() async {
    debugPrint('[WebSocketDemo] _connect 被调用, 当前状态: $_currentState, isConnecting: $_isConnecting');
    if (_isConnecting) {
      _appendLog('正在连接中，请稍候...', LogType.warning);
      return;
    }

    _isConnecting = true;
    _appendLog('初始化连接...', LogType.info);

    try {
      debugPrint('[WebSocketDemo] 取消之前的订阅');
      await _eventSubscription?.cancel();
      await _stateSubscription?.cancel();
      await _client?.dispose();

      debugPrint('[WebSocketDemo] 创建自定义日志实例');
      _logger = _createCustomLogger();
      _appendLog('日志实例已创建: level=$_currentLogLevel, enabled=$_loggingEnabled', LogType.info);

      debugPrint('[WebSocketDemo] 创建配置');
      final config = PDLongLinkConfig(
        uri: Uri.parse('wss://echo.websocket.org'),
        transportMode: PDLongLinkTransportMode.auto,
        headers: {'Origin': 'https://example.com'},
        connectTimeout: const Duration(seconds: 10),
        reconnectPolicy: const PDReconnectPolicy(
          maxAttempts: 10,
          baseDelay: Duration(seconds: 1),
          maxDelay: Duration(seconds: 30),
          jitterRatio: 0.1,
          reconnectOnResume: true,
          enableInBackground: false,
        ),
        heartbeatConfig: PDHeartbeatConfig(
          interval: const Duration(seconds: 30),
          timeout: const Duration(seconds: 10),
          pingMessage: 'ping',
          pongMessage: _pongMessageController.text.trim().isEmpty ? 'pong' : _pongMessageController.text.trim(),
        ),
        messageQueueConfig: PDMessageQueueConfig(
          enabled: _messageQueueEnabled,
          maxSize: _messageQueueMaxSize,
          overflowStrategy: _messageQueueOverflowStrategy,
        ),
        autoConnect: false,
        enableHeartbeat: true,
        logger: _logger,
      );

      debugPrint('[WebSocketDemo] 创建 PDLongLinkClient');
      _client = PDLongLinkClient(config: config);

      debugPrint('[WebSocketDemo] 监听状态变化');
      _stateSubscription = _client!.state.listen((state) {
        debugPrint('[WebSocketDemo] 状态变化: $state');
        setState(() => _currentState = state);
        _appendLog('状态变化: $state', LogType.state);
      });

      debugPrint('[WebSocketDemo] 监听事件');
      _eventSubscription = _client!.events.listen((event) {
        debugPrint(
            '[WebSocketDemo] 收到事件: ${event.type}, text: ${event.text?.substring(0, event.text!.length > 50 ? 50 : event.text!.length)}');
        switch (event.type) {
          case PDLongLinkEventType.message:
            _appendLog('收到消息: ${event.text ?? '${event.binary?.length ?? 0} bytes'}', LogType.message);
            setState(() {
              _lastEventIdDisplay = _client?.lastEventId ?? 'N/A';
            });
            break;
          case PDLongLinkEventType.error:
            final errorCodeStr = event.errorCode != null ? ' [errorCode: ${event.errorCode}]' : '';
            _appendLog('错误: ${event.error}$errorCodeStr', LogType.error);
            setState(() {
              _isConnecting = false;
              _lastEventIdDisplay = _client?.lastEventId ?? 'N/A';
            });
            break;
          case PDLongLinkEventType.open:
            _appendLog('连接成功', LogType.success);
            setState(() {
              _isConnecting = false;
              _queueSize = 0;
              _lastEventIdDisplay = _client?.lastEventId ?? 'N/A';
            });
            break;
          case PDLongLinkEventType.close:
            final errorCodeStr = event.errorCode != null ? ' [errorCode: ${event.errorCode}]' : '';
            _appendLog('连接关闭 (code: ${event.closeCode})$errorCodeStr', LogType.info);
            setState(() {
              _isConnecting = false;
              _lastEventIdDisplay = _client?.lastEventId ?? 'N/A';
            });
            break;
          case PDLongLinkEventType.ping:
            _appendLog('发送心跳', LogType.debug);
            break;
          case PDLongLinkEventType.pong:
            _appendLog('收到心跳响应', LogType.debug);
            break;
        }
      });

      debugPrint('[WebSocketDemo] 调用 connect()');
      await _client!.connect();
      debugPrint('[WebSocketDemo] connect() 完成');
    } catch (e) {
      debugPrint('[WebSocketDemo] 连接异常: $e');
      _appendLog('连接失败: $e', LogType.error);
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _disconnect() async {
    debugPrint('[WebSocketDemo] _disconnect 被调用');
    await _client?.disconnect();
    _appendLog('手动断开连接', LogType.info);
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    debugPrint('[WebSocketDemo] _sendMessage: $text');
    try {
      final wasConnected = _currentState == PDLongLinkState.connected;
      await _client?.sendText(text);
      if (wasConnected) {
        _appendLog('发送: $text', LogType.sent);
      } else {
        setState(() {
          if (_queueSize < _messageQueueMaxSize) {
            _queueSize++;
          } else if (_messageQueueOverflowStrategy == PDMessageQueueOverflowStrategy.dropOldest) {
            // 保持不变
          } else {
            // dropNewest，不增加
          }
        });
        _appendLog('消息已加入队列: $text (队列大小: $_queueSize)', LogType.info);
      }
      _messageController.clear();
    } catch (e) {
      debugPrint('[WebSocketDemo] 发送失败: $e');
      _appendLog('发送失败: $e', LogType.error);
    }
  }

  Future<void> _sendBinary() async {
    final binary = Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]);

    debugPrint('[WebSocketDemo] _sendBinary: ${binary.length} bytes');
    try {
      final wasConnected = _currentState == PDLongLinkState.connected;
      await _client?.sendBinary(binary);
      if (wasConnected) {
        _appendLog('发送二进制: ${binary.length} bytes', LogType.sent);
      } else {
        setState(() {
          if (_queueSize < _messageQueueMaxSize) {
            _queueSize++;
          } else if (_messageQueueOverflowStrategy == PDMessageQueueOverflowStrategy.dropOldest) {
            // 保持不变
          } else {
            // dropNewest，不增加
          }
        });
        _appendLog('二进制消息已加入队列 (队列大小: $_queueSize)', LogType.info);
      }
    } catch (e) {
      debugPrint('[WebSocketDemo] 发送二进制失败: $e');
      _appendLog('发送二进制失败: $e', LogType.error);
    }
  }

  void _toggleLogging(bool enabled) {
    setState(() => _loggingEnabled = enabled);
    _client?.enableLogging(enabled);
    _appendLog('日志 ${enabled ? '启用' : '禁用'}', LogType.info);
  }

  void _changeLogLevel(PDLogLevel? level) {
    if (level == null) return;
    setState(() => _currentLogLevel = level);
    _client?.setLogLevel(level);
    _appendLog('日志级别已更改为: $level', LogType.info);
  }

  void _toggleMessageQueue(bool enabled) {
    setState(() => _messageQueueEnabled = enabled);
    _appendLog('消息队列 ${enabled ? '启用' : '禁用'}，重新连接以生效', LogType.info);
    _reconnectWithNewConfig();
  }

  void _changeOverflowStrategy(PDMessageQueueOverflowStrategy? strategy) {
    if (strategy == null) return;
    setState(() => _messageQueueOverflowStrategy = strategy);
    _appendLog('溢出策略已更改为: ${strategy == PDMessageQueueOverflowStrategy.dropOldest ? '丢弃最早' : '丢弃最新'}，重新连接以生效', LogType.info);
    _reconnectWithNewConfig();
  }

  void _onPongMessageChanged() {
    _appendLog('pong 消息已更改为: ${_pongMessageController.text}，重新连接以生效', LogType.info);
    _reconnectWithNewConfig();
  }

  Future<void> _reconnectWithNewConfig() async {
    if (_client == null) return;
    final wasConnected = _currentState == PDLongLinkState.connected || _currentState == PDLongLinkState.connecting;
    if (wasConnected) {
      await _disconnect();
      await _connect();
    }
  }

  Widget _buildStatusIndicator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _getStateColor(),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _getStateColor(),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _getStateText(),
              style: TextStyle(
                color: _getStateColor(),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              'lastEventId:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(width: 4),
            Text(
              _lastEventIdDisplay,
              style: const TextStyle(fontSize: 12, fontFamily: 'Monospace', color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text(
              '队列大小:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(width: 4),
            Text(
              '$_queueSize / $_messageQueueMaxSize',
              style: const TextStyle(fontSize: 12, fontFamily: 'Monospace', color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }

  String _getStateText() {
    switch (_currentState) {
      case PDLongLinkState.disconnected:
        return '已断开';
      case PDLongLinkState.connecting:
        return '连接中...';
      case PDLongLinkState.connected:
        return '已连接';
      case PDLongLinkState.reconnecting:
        return '重连中...';
      case PDLongLinkState.failed:
        return '连接失败';
    }
  }

  Color _getStateColor() {
    switch (_currentState) {
      case PDLongLinkState.disconnected:
        return Colors.grey;
      case PDLongLinkState.connecting:
      case PDLongLinkState.reconnecting:
        return Colors.orange;
      case PDLongLinkState.connected:
        return Colors.green;
      case PDLongLinkState.failed:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebSocket 演示'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildStatusIndicator(),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isConnecting
                                  ? null
                                  : (_currentState == PDLongLinkState.connected ? _disconnect : _connect),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    _currentState == PDLongLinkState.connected ? Colors.red : Colors.blue,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: _isConnecting
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : Text(_currentState == PDLongLinkState.connected ? '断开连接' : '连接'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '日志配置',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Text('日志开关:'),
                                  const SizedBox(width: 12),
                                  Switch(
                                    value: _loggingEnabled,
                                    onChanged: _toggleLogging,
                                    activeColor: Colors.blue,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text('日志级别:'),
                                  const SizedBox(width: 12),
                                  DropdownButton<PDLogLevel>(
                                    value: _currentLogLevel,
                                    items: PDLogLevel.values.map((level) {
                                      return DropdownMenuItem(
                                        value: level,
                                        child: Text(level.name.toUpperCase()),
                                      );
                                    }).toList(),
                                    onChanged: _changeLogLevel,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '日志级别说明:\n- DEBUG: 显示所有日志\n- INFO: 显示信息、警告和错误\n- WARNING: 仅显示警告和错误\n- ERROR: 仅显示错误',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '消息队列',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Text('启用队列:'),
                                  const SizedBox(width: 12),
                                  Switch(
                                    value: _messageQueueEnabled,
                                    onChanged: _toggleMessageQueue,
                                    activeColor: Colors.blue,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text('溢出策略:'),
                                  const SizedBox(width: 12),
                                  DropdownButton<PDMessageQueueOverflowStrategy>(
                                    value: _messageQueueOverflowStrategy,
                                    items: const [
                                      DropdownMenuItem(
                                        value: PDMessageQueueOverflowStrategy.dropOldest,
                                        child: Text('丢弃最早'),
                                      ),
                                      DropdownMenuItem(
                                        value: PDMessageQueueOverflowStrategy.dropNewest,
                                        child: Text('丢弃最新'),
                                      ),
                                    ],
                                    onChanged: _changeOverflowStrategy,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '消息队列说明:\n- 断开连接时消息自动入队\n- 连接恢复后自动发送\n- 可配置队列最大容量和溢出策略',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '心跳配置',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Text('pong 消息:'),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _pongMessageController,
                                      decoration: const InputDecoration(
                                        hintText: 'pong',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      onSubmitted: (_) => _onPongMessageChanged(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _onPongMessageChanged,
                                    child: const Text('应用'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '心跳说明:\n- ping: 定期发送的心跳消息\n- pong: 心跳响应消息\n- 超时未收到 pong 会触发重连',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              decoration: const InputDecoration(
                                hintText: '输入消息...',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.message),
                              ),
                              enabled: true,
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _sendMessage,
                            child: const Text('发送'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _sendBinary,
                            child: const Text('二进制'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info, size: 16, color: Colors.grey),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '服务器: wss://echo.websocket.org (回显所有消息)\n注: 自定义日志回调会将SDK内部日志显示在下方日志区',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    Flexible(
                      fit: FlexFit.loose,
                      child: SizedBox(
                        height: 300,
                        child: ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            return LogItem(_logs[index]);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
