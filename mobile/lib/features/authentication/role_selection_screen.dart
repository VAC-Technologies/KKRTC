import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/api_config.dart';
import '../../core/storage/app_state_storage.dart';
import '../../shared/models/user_model.dart';
import '../../shared/repositories/auth_repository.dart';
import '../../shared/widgets/kkrtc_logo.dart';
import '../../shared/widgets/vac_teams_footer.dart';
import '../driver/driver_dashboard_screen.dart';
import '../passenger/passenger_main_screen.dart';
import 'login_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  void _selectPassenger(BuildContext context) async {
    await AppStateStorage.saveRole(UserRole.passenger);
    await AppStateStorage.saveAuthenticatedSession(
      role: UserRole.passenger,
      phoneNumber: '',
    );
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const PassengerMainScreen()),
    );
  }

  void _selectPilot(BuildContext context) async {
    await AppStateStorage.saveRole(UserRole.pilot);
    if (!context.mounted) return;

    if (ApiConfig.demoPilotMode) {
      try {
        await AuthRepository.instance.loginDemoPilot();
        if (!context.mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const DriverDashboardScreen(),
          ),
        );
        return;
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Demo Pilot Mode unavailable: $e')),
        );
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LoginScreen(role: UserRole.pilot),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose account type')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 20),
            const Center(child: KkrtcLogo(size: 76, showText: false)),
            const SizedBox(height: 24),
            Text(
              'Welcome to KKRTC',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Select how you use the service. Passengers access services immediately. Pilots sign in with authorized duty credentials.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.mutedBlueGrey),
            ),
            const SizedBox(height: 32),
            _RoleCard(
              title: 'Passenger',
              badgeText: 'Instant Access (No sign-in)',
              description:
                  'Search routes, live buses, and track your journey directly.',
              icon: Icons.person_pin_circle_rounded,
              onTap: () => _selectPassenger(context),
            ),
            const SizedBox(height: 16),
            _RoleCard(
              title: 'Pilot',
              badgeText: 'Sign In Required',
              description: 'Official KKRTC driver and conductor portal for duty dispatch and live GPS sharing.',
              icon: Icons.badge_rounded,
              onTap: () => _selectPilot(context),
            ),
            const SizedBox(height: 24),
            const VacTeamsFooter(padding: EdgeInsets.symmetric(vertical: 16)),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
    this.badgeText,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, color: AppColors.brightCyan, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (badgeText != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.oceanBlue.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badgeText!,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brightCyan,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(color: AppColors.mutedBlueGrey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.brightCyan),
            ],
          ),
        ),
      ),
    );
  }
}
