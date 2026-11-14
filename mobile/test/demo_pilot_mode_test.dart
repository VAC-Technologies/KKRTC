import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkrtc_bus/core/network/api_config.dart';
import 'package:kkrtc_bus/core/storage/app_state_storage.dart';
import 'package:kkrtc_bus/features/authentication/role_selection_screen.dart';
import 'package:kkrtc_bus/features/driver/driver_dashboard_screen.dart';

void main() {
  setUp(() {
    AppStateStorage.setMockInitialValues({});
    ApiConfig.demoPilotMode = false;
  });

  tearDown(() {
    ApiConfig.demoPilotMode = false;
  });

  group('Demo Pilot Mode & Authentication Flow Tests', () {
    testWidgets(
      'when demoPilotMode is false, selecting Pilot opens normal LoginScreen',
      (WidgetTester tester) async {
        ApiConfig.demoPilotMode = false;

        await tester.pumpWidget(const MaterialApp(home: RoleSelectionScreen()));
        await tester.tap(find.text('Pilot'));
        await tester.pumpAndSettle();

        // Must show normal login screen, requiring phone number
        expect(find.text('Welcome to KKRTC'), findsOneWidget);
        expect(find.text('Send OTP'), findsOneWidget);
        expect(find.text('Pilot Journey'), findsNothing);
        expect(find.text('DEMO PILOT MODE (CAMPUS TESTING)'), findsNothing);
      },
    );

    testWidgets(
      'when demoPilotMode is true, selecting Pilot bypasses login and opens DriverDashboard with Demo Banner',
      (WidgetTester tester) async {
        ApiConfig.demoPilotMode = true;

        await tester.pumpWidget(const MaterialApp(home: RoleSelectionScreen()));
        await tester.tap(find.text('Pilot'));
        await tester.pumpAndSettle();

        // Must directly open DriverDashboardScreen without login/OTP
        expect(find.text('Pilot Journey'), findsOneWidget);
        expect(find.text('Send OTP'), findsNothing);
        expect(find.text('Verify OTP'), findsNothing);

        // Must display prominent Demo Pilot banner
        expect(find.text('DEMO PILOT MODE (CAMPUS TESTING)'), findsOneWidget);
        expect(find.textContaining('Pilot: Anil'), findsOneWidget);
        expect(find.textContaining('Assigned Bus: KA-34-A-1001'), findsOneWidget);
      },
    );

    testWidgets(
      'in Demo Pilot Mode, signing out returns to RoleSelectionScreen cleanly',
      (WidgetTester tester) async {
        ApiConfig.demoPilotMode = true;

        await tester.pumpWidget(const MaterialApp(home: DriverDashboardScreen()));
        expect(find.text('Pilot Journey'), findsOneWidget);
        expect(find.text('DEMO PILOT MODE (CAMPUS TESTING)'), findsOneWidget);

        // Tap Sign Out icon
        await tester.tap(find.byIcon(Icons.logout_rounded));
        await tester.pumpAndSettle();

        expect(find.text('Confirm sign out'), findsNothing); // Dialog title is 'Sign Out'
        expect(find.text('Sign Out'), findsWidgets);

        // Confirm sign out in dialog
        final signOutButtons = find.widgetWithText(ElevatedButton, 'Sign Out');
        expect(signOutButtons, findsOneWidget);
        await tester.tap(signOutButtons);
        await tester.pumpAndSettle();

        // Must return to RoleSelectionScreen
        expect(find.text('Welcome to KKRTC'), findsOneWidget);
        expect(find.text('Passenger'), findsOneWidget);
        expect(find.text('Pilot'), findsOneWidget);
      },
    );
  });
}
