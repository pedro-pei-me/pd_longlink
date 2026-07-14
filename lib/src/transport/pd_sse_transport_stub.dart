import '../pd_config.dart';
import '../pd_transport.dart';

PDLongLinkTransport createSseTransport({PDSseConfig? sseConfig}) {
  throw UnsupportedError('SSE transport not supported on this platform');
}