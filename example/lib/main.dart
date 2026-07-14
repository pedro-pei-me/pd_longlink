import 'package:flutter/material.dart';

import 'sse_demo.dart';
import 'web_socket_demo.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PD LongLink 示例',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[HomePage] 构建首页');
    return Scaffold(
      appBar: AppBar(
        title: const Text('PD LongLink'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('选择演示'),
          const SizedBox(height: 12),
          _DemoCard(
            icon: Icons.link,
            title: 'WebSocket',
            subtitle: '全双工双向通信',
            color: Colors.blue,
            onTap: () {
              debugPrint('[HomePage] 点击 WebSocket 演示');
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WebSocketDemoPage()),
              );
            },
          ),
          const SizedBox(height: 8),
          _DemoCard(
            icon: Icons.stream,
            title: 'Server-Sent Events (SSE)',
            subtitle: '服务器到客户端单向流',
            color: Colors.green,
            onTap: () {
              debugPrint('[HomePage] 点击 SSE 演示');
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SseDemoPage()),
              );
            },
          ),
          const SizedBox(height: 24),
          const _SectionTitle('核心功能'),
          const SizedBox(height: 12),
          const _FeatureGrid([
            _FeatureItem('🔄', '自动重连', '指数退避算法'),
            _FeatureItem('❤️', '心跳保活', '超时检测'),
            _FeatureItem('📱', '生命周期', '感知应用状态'),
            _FeatureItem('🔀', '多模式', 'WebSocket / SSE'),
            _FeatureItem('📡', '跨平台', '手机/Web/电脑'),
            _FeatureItem('⚡', '二进制', '支持二进制消息'),
            _FeatureItem('📝', '实例日志', '独立日志配置'),
            _FeatureItem('🔍', '动态调级', '运行时日志控制'),
          ]),
          const SizedBox(height: 24),
          const _SectionTitle('公开测试服务器'),
          const SizedBox(height: 12),
          const _ServerInfo(
            protocol: 'WebSocket',
            url: 'wss://echo.websocket.org',
            description: 'Echo服务器 - 返回所有发送的消息',
          ),
          const SizedBox(height: 8),
          const _ServerInfo(
            protocol: 'SSE',
            url: 'http://localhost:3000/sse',
            description:
                '本地SSE测试服务器（需先启动）\n终端执行:\n cd example/test_server && node sse_server.js \n结果:\n SSE Test Server running on http://localhost:3000 \n SSE endpoint: http://localhost:3000/sse',
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

class _DemoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _DemoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  final List<_FeatureItem> items;

  const _FeatureGrid(this.items);

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        return SizedBox(
          width: 120,
          height: 80,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[50],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(item.icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 3),
                Text(item.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text(item.subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FeatureItem {
  final String icon;
  final String title;
  final String subtitle;

  const _FeatureItem(this.icon, this.title, this.subtitle);
}

class _ServerInfo extends StatelessWidget {
  final String protocol;
  final String url;
  final String description;

  const _ServerInfo({
    required this.protocol,
    required this.url,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              protocol,
              style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 4),
            Text(url, style: const TextStyle(fontFamily: 'Monospace', fontSize: 12)),
            const SizedBox(height: 4),
            Text(description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

enum LogType {
  info,
  success,
  error,
  warning,
  message,
  sent,
  state,
  debug,
}

class LogEntry {
  final String message;
  final LogType type;
  final DateTime timestamp;

  LogEntry(this.message, this.type) : timestamp = DateTime.now();
}

class LogItem extends StatelessWidget {
  final LogEntry entry;

  const LogItem(this.entry, {super.key});

  Color _getTextColor() {
    switch (entry.type) {
      case LogType.success:
        return Colors.green;
      case LogType.error:
        return Colors.red;
      case LogType.warning:
        return Colors.orange;
      case LogType.message:
        return Colors.blue;
      case LogType.sent:
        return Colors.purple;
      case LogType.state:
        return Colors.indigo;
      case LogType.debug:
        return Colors.grey;
      case LogType.info:
        return Colors.black87;
    }
  }

  String _getTime() {
    return entry.timestamp.toString().split(' ')[1].substring(0, 12);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _getTime(),
            style: const TextStyle(fontSize: 11, fontFamily: 'Monospace', color: Colors.grey),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'Monospace',
                color: _getTextColor(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
