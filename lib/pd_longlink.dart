/// Production-grade long connection library for Flutter.
///
/// Supports WebSocket, System WebSocket and Server-Sent Events (SSE) with
/// auto-reconnect, heartbeat, message queue and lifecycle awareness.
///
/// ## Getting Started
///
/// ```dart
/// final config = PDLongLinkConfig(
///   uri: Uri.parse('wss://example.com'),
/// );
/// final client = PDLongLinkClient(config: config);
/// await client.connect();
/// ```
library pd_longlink;

export 'src/pd_long_link_core.dart';
export 'src/pd_long_link_client.dart';
export 'src/pd_logger.dart';
export 'src/pd_log_types.dart';
