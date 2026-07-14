import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:pd_longlink/pd_longlink.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PDLongLinkConfig test', (WidgetTester tester) async {
    final config = PDLongLinkConfig(
      uri: Uri.parse('wss://example.com'),
      transportMode: PDLongLinkTransportMode.auto,
    );

    expect(config.uri.toString(), 'wss://example.com');
    expect(config.transportMode, PDLongLinkTransportMode.auto);
  });

  testWidgets('PDLongLinkState values', (WidgetTester tester) async {
    expect(PDLongLinkState.disconnected.name, 'disconnected');
    expect(PDLongLinkState.connecting.name, 'connecting');
    expect(PDLongLinkState.connected.name, 'connected');
    expect(PDLongLinkState.reconnecting.name, 'reconnecting');
    expect(PDLongLinkState.failed.name, 'failed');
  });
}
