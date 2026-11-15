import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkrtc_bus/core/network/api_config.dart';
import 'package:kkrtc_bus/core/storage/app_state_storage.dart';
import 'package:kkrtc_bus/features/driver/driver_dashboard_screen.dart';
import 'package:kkrtc_bus/shared/repositories/auth_repository.dart';

void main() {
  group('Active Trip Recovery & Token Refresh Unit Tests', () {
    setUp(() {
      AppStateStorage.setMockInitialValues({});
      ApiConfig.demoPilotMode = true;
    });

    test('AppStateStorage token save, retrieval, and clear', () async {
      await AppStateStorage.saveTokens(
        access: 'test_access_token_123',
        refresh: 'test_refresh_token_456',
      );

      expect(await AppStateStorage.getAccessToken(), 'test_access_token_123');
      expect(await AppStateStorage.getRefreshToken(), 'test_refresh_token_456');

      await AppStateStorage.clearTokens();
      expect(await AppStateStorage.getAccessToken(), isNull);
      expect(await AppStateStorage.getRefreshToken(), isNull);
    });

    test('AppStateStorage pilot active trip ID persistence and clear', () async {
      await AppStateStorage.savePilotActiveTripId(7);
      expect(await AppStateStorage.getPilotActiveTripId(), 7);

      await AppStateStorage.savePilotActiveTripId(null);
      expect(await AppStateStorage.getPilotActiveTripId(), isNull);
    });

    testWidgets(
      'DriverDashboard renders restored active trip card when trip ID is present in state',
      (WidgetTester tester) async {
        AppStateStorage.setMockInitialValues({
          'kkrtc_pilot_active_trip_id': 7,
          'kkrtc_jwt_access': 'valid_token',
        });

        await tester.pumpWidget(
          const MaterialApp(home: DriverDashboardScreen()),
        );
        await tester.pumpAndSettle();

        // Must display active trip card
        expect(find.text('Active trip #7'), findsOneWidget);
        expect(find.text('GPS BROADCASTING'), findsOneWidget);
        expect(find.text('End trip'), findsOneWidget);

        // Start trip button must NOT be present when a trip is active
        expect(find.text('Start trip'), findsNothing);
      },
    );

    testWidgets(
      'DriverDashboard renders selection form when no active trip exists',
      (WidgetTester tester) async {
        AppStateStorage.setMockInitialValues({});

        await tester.pumpWidget(
          const MaterialApp(home: DriverDashboardScreen()),
        );
        await tester.pumpAndSettle();

        expect(find.text('Driver Name'), findsOneWidget);
        expect(find.text('Route ID'), findsOneWidget);
        expect(find.text('Bus ID / Bus Number'), findsOneWidget);
        expect(find.text('Confirm journey'), findsOneWidget);
        expect(find.textContaining('Active trip #'), findsNothing);
      },
    );

    test('loginDemoPilot switches driver identity and persists tokens per driver', () async {
      final repo = MockAuthRepository();

      // Login as default (Anil)
      final anilSession = await repo.loginDemoPilot();
      expect(anilSession['pilot']['username'], 'Anil');
      expect(anilSession['assigned_bus']['registration_number'], 'KA-35-F-1234');
      expect(await AppStateStorage.getAccessToken(), 'mock_demo_access_token_4');

      // Login as Tester1 (driverId: 5)
      final testerSession = await repo.loginDemoPilot(driverId: 5);
      expect(testerSession['pilot']['username'], 'Tester1');
      expect(testerSession['pilot']['badge_number'], 'KKRTC-P-02');
      expect(testerSession['assigned_bus']['registration_number'], 'KA-35-F-1235');
      expect(await AppStateStorage.getAccessToken(), 'mock_demo_access_token_5');
    });
  });
}
