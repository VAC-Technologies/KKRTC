import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkrtc_bus/core/storage/app_state_storage.dart';
import 'package:kkrtc_bus/features/authentication/role_selection_screen.dart';
import 'package:kkrtc_bus/features/passenger/passenger_main_screen.dart';
import 'package:kkrtc_bus/shared/models/user_model.dart';

void main() {
  setUp(() {
    AppStateStorage.setMockInitialValues({});
  });

  group('Passenger UX & Bottom Navigation Tests', () {
    testWidgets(
      'Passenger selection provides instant access to PassengerMainScreen',
      (WidgetTester tester) async {
        await tester.pumpWidget(const MaterialApp(home: RoleSelectionScreen()));
        await tester.pumpAndSettle();

        // Tap Passenger card
        await tester.tap(find.text('Passenger'));
        await tester.pumpAndSettle();

        // Verify immediate landing on PassengerMainScreen (no Login or OTP screen shown)
        expect(find.byType(PassengerMainScreen), findsOneWidget);
        expect(find.text('Where Is My Bus?'), findsOneWidget);
        expect(find.text('Verify OTP'), findsNothing);
        expect(find.text('Mobile Number'), findsNothing);

        // Verify stored role is passenger and authenticated session is established
        expect(await AppStateStorage.getRole(), UserRole.passenger);
        expect(await AppStateStorage.isAuthenticated(), isTrue);
      },
    );

    testWidgets('Bottom navigation contains only Home and Profile options', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PassengerMainScreen()));
      await tester.pumpAndSettle();

      // NavigationBar must have exactly 2 destinations: Home and Profile
      expect(find.byType(NavigationDestination), findsNWidgets(2));
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      // Verify removed duplicate tabs
      expect(find.text('Search'), findsNothing);
      expect(find.text('Track'), findsNothing);
      expect(find.text('Trips'), findsNothing);
    });

    testWidgets('Switching between Home and Profile tabs persists state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PassengerMainScreen()));
      await tester.pumpAndSettle();

      // Tap Profile
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      // Expect Profile screen content
      expect(find.text('Preferences & Language'), findsOneWidget);
      expect(find.text('Dark Theme'), findsOneWidget);
      expect(await AppStateStorage.getPassengerTabIndex(), 1);

      // Tap Home
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(await AppStateStorage.getPassengerTabIndex(), 0);
    });

    test(
      'Theme preference can be saved and retrieved in AppStateStorage',
      () async {
        expect(await AppStateStorage.getThemeMode(), ThemeMode.light);

        await AppStateStorage.saveThemeMode(ThemeMode.dark);
        expect(await AppStateStorage.getThemeMode(), ThemeMode.dark);
        expect(AppStateStorage.themeNotifier.value, ThemeMode.dark);

        await AppStateStorage.saveThemeMode(ThemeMode.light);
        expect(await AppStateStorage.getThemeMode(), ThemeMode.light);
        expect(AppStateStorage.themeNotifier.value, ThemeMode.light);
      },
    );
  });
}
