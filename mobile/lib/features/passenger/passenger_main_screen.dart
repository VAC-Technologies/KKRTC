import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/storage/app_state_storage.dart';
import '../profile/profile_screen.dart';
import 'passenger_home_tab.dart';

class PassengerMainScreen extends StatefulWidget {
  const PassengerMainScreen({super.key});

  @override
  State<PassengerMainScreen> createState() => _PassengerMainScreenState();
}

class _PassengerMainScreenState extends State<PassengerMainScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _restoreSavedTab();
  }

  Future<void> _restoreSavedTab() async {
    final savedIndex = await AppStateStorage.getPassengerTabIndex();
    if (mounted && (savedIndex == 0 || savedIndex == 1)) {
      setState(() => _currentIndex = savedIndex);
    }
  }

  void _navigateTo(int index) {
    if (index == 0 || index == 1) {
      setState(() => _currentIndex = index);
      AppStateStorage.savePassengerTabIndex(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      PassengerHomeTab(onNavigateToProfile: () => _navigateTo(1)),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _navigateTo,
        backgroundColor: AppColors.white,
        elevation: 8,
        shadowColor: AppColors.deepNavy.withValues(alpha: 0.1),
        indicatorColor: AppColors.warmLightYellow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: AppStrings.navHome,
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: AppStrings.navProfile,
          ),
        ],
      ),
    );
  }
}
