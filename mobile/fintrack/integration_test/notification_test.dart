import 'package:fintrack/data/api.dart';
import 'package:fintrack/data/notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android notification resources initialize', (tester) async {
    final notifications = PushNotifications(CloudApi(), (_) {});
    await notifications.initialize();
    expect(notifications.ready, isTrue);
    await notifications.dispose();
  });
}
