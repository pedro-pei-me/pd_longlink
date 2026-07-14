import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pd_longlink/pd_longlink.dart';

import 'main.dart';

class SseDemoPage extends StatefulWidget {
  const SseDemoPage({super.key});

  @override
  State<SseDemoPage> createState() => _SseDemoPageState();
}

class _SseDemoPageState extends State<SseDemoPage> {
  PDLongLinkClient? _client;
  PDLogger? _logger;
  StreamSubscription<PDLongLinkEvent>? _eventSubscription;
  StreamSubscription<PDLongLinkState>? _stateSubscription;
  final List<LogEntry> _logs = [];
  PDLongLinkState _currentState = PDLongLinkState.disconnected;
  bool _isConnecting = false;
  bool _loggingEnabled = true;
  PDLogLevel _currentLogLevel = PDLogLevel.debug;
  String? _lastEventId;
  bool _parseSseFormat = false;
  int _reconnectCount = 0;

  @override
  void dispose() {
    debugPrint('[SseDemo] dispose 开始');
    _eventSubscription?.cancel();
    _stateSubscription?.cancel();
    _client?.dispose();
    debugPrint('[SseDemo] dispose 完成');
    super.dispose();
  }

  void _appendLog(String message, [LogType type = LogType.info]) {
    debugPrint('[SseDemo] [$type] $message');
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
        String type;
        switch (logData.level) {
          case PDLogLevel.debug:
            type = 'DEBUG';
            break;
          case PDLogLevel.info:
            type = 'INFO';
            break;
          case PDLogLevel.warning:
            type = 'WARN';
            break;
          case PDLogLevel.error:
            type = 'ERROR';
            break;
        }
        _appendLog('[SDK] [$type] ${logData.module}: ${logData.message}', LogType.debug);
      },
    );
  }

  Future<void> _connect() async {
    debugPrint('[SseDemo] _connect 被调用, 当前状态: $_currentState, isConnecting: $_isConnecting');
    if (_isConnecting) {
      _appendLog('正在连接中，请稍候...', LogType.warning);
      return;
    }

    _isConnecting = true;
    _appendLog('初始化 SSE 连接...', LogType.info);

    try {
      debugPrint('[SseDemo] 取消之前的订阅');
      await _eventSubscription?.cancel();
      await _stateSubscription?.cancel();
      await _client?.dispose();

      debugPrint('[SseDemo] 创建自定义日志实例');
      _logger = _createCustomLogger();
      _appendLog('日志实例已创建: level=$_currentLogLevel, enabled=$_loggingEnabled', LogType.info);

      debugPrint('[SseDemo] 创建配置');
      final config = PDLongLinkConfig(
        uri: Uri.parse('http://localhost:3000/sse'),
        transportMode: PDLongLinkTransportMode.sse,
        headers: {
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
        },
        connectTimeout: const Duration(seconds: 10),
        reconnectPolicy: const PDReconnectPolicy(
          maxAttempts: 10,
          baseDelay: Duration(seconds: 1),
          maxDelay: Duration(seconds: 30),
        ),
        sseConfig: PDSseConfig(
          method: 'GET',
          parseSseFormat: _parseSseFormat,
          lastEventId: _lastEventId,
        ),
        autoConnect: false,
        enableHeartbeat: false,
        logger: _logger,
      );

      debugPrint('[SseDemo] 创建 PDLongLinkClient');
      _client = PDLongLinkClient(config: config);

      debugPrint('[SseDemo] 监听状态变化');
      _stateSubscription = _client!.state.listen((state) {
        debugPrint('[SseDemo] 状态变化: $state');
        setState(() {
          _currentState = state;
          if (state == PDLongLinkState.reconnecting) {
            _reconnectCount++;
          } else if (state == PDLongLinkState.connected) {
            _reconnectCount = 0;
          }
        });
        _appendLog('状态变化: $state', LogType.state);
      });

      debugPrint('[SseDemo] 监听事件');
      _eventSubscription = _client!.events.listen((event) {
        debugPrint('[SseDemo] 收到事件: ${event.type}');
        switch (event.type) {
          case PDLongLinkEventType.message:
            final text = event.text ?? '';
            final displayText = text.length > 100 ? '${text.substring(0, 100)}...' : text;
            _appendLog('收到消息: $displayText', LogType.message);
            setState(() {
              _lastEventId = _client?.lastEventId;
            });
            break;
          case PDLongLinkEventType.error:
            final errorCodeStr = event.errorCode != null ? ' [${event.errorCode!.name}]' : '';
            _appendLog('错误$errorCodeStr: ${event.error}', LogType.error);
            setState(() => _isConnecting = false);
            break;
          case PDLongLinkEventType.open:
            _appendLog('SSE 连接已建立', LogType.success);
            setState(() => _isConnecting = false);
            break;
          case PDLongLinkEventType.close:
            _appendLog('SSE 连接关闭', LogType.info);
            setState(() {
              _isConnecting = false;
              _lastEventId = _client?.lastEventId;
            });
            break;
          default:
            break;
        }
      });

      debugPrint('[SseDemo] 调用 connect()');
      await _client!.connect();
      debugPrint('[SseDemo] connect() 完成');
    } catch (e) {
      debugPrint('[SseDemo] 连接异常: $e');
      _appendLog('连接失败: $e', LogType.error);
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _disconnect() async {
    debugPrint('[SseDemo] _disconnect 被调用');
    setState(() {
      _lastEventId = _client?.lastEventId;
      _reconnectCount = 0;
    });
    await _client?.dispose();
    _appendLog('手动断开连接', LogType.info);
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

  void _toggleParseSseFormat(bool value) {
    setState(() => _parseSseFormat = value);
    _appendLog('解析SSE格式已${value ? '开启' : '关闭'}，重新连接后生效', LogType.info);
  }

  Widget _buildStatusIndicator() {
    return Row(
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
        return '重连中... (第 $_reconnectCount 次)';
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
        title: const Text('SSE 演示'),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStatusIndicator(),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text(
                                'Last-Event-ID:',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _lastEventId ?? '无',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    fontFamily: 'Monospace',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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
                                    _currentState == PDLongLinkState.connected ? Colors.red : Colors.green,
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
                                    activeColor: Colors.green,
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
                                'SSE 配置',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Text('解析SSE格式:'),
                                  const SizedBox(width: 12),
                                  Switch(
                                    value: _parseSseFormat,
                                    onChanged: _toggleParseSseFormat,
                                    activeColor: Colors.green,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                '切换后需重新连接生效',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info, size: 16, color: Colors.grey),
                                SizedBox(width: 8),
                                Text(
                                  '服务器: 本地 SSE 测试服务器',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Text(
                              'http://localhost:3000/sse',
                              style: TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'Monospace'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          border: Border.all(color: Colors.blue.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, size: 20, color: Colors.blue),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'SSE 是单向通信协议，消息仅从服务器推送至客户端。如需双向通信，请使用 WebSocket。',
                                style: TextStyle(fontSize: 12, color: Colors.blue),
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