import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'activity_screen.dart';
import 'admin_users_screen.dart';
import 'app_theme.dart';
import 'auth/auth_provider.dart';
import 'behaviour_analysis_screen.dart';
import 'debug_screen.dart';
import 'insights_screen.dart';
import 'particle_background.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    final tileColor = color ?? AppColors.textPrimary;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color != null
                    ? AppColors.dangerTint
                    : AppColors.accentTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: color ?? AppColors.accentStrong,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w600, color: tileColor),
              ),
            ),
            if (color == null)
              Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ParticleBackground(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.dark,
                  backgroundImage: auth.photoUrl.isNotEmpty
                      ? NetworkImage(auth.photoUrl)
                      : null,
                  child: auth.photoUrl.isEmpty
                      ? Icon(Icons.person, color: AppColors.accent)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.username.isEmpty ? 'SmartPoc user' : auth.username,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        auth.email,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (auth.isSuperAdmin) ...[
              _tile(
                context,
                icon: Icons.admin_panel_settings_outlined,
                title: 'User Management',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _tile(
              context,
              icon: Icons.insights_outlined,
              title: 'Your Insights',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const InsightsScreen())),
            ),
            const SizedBox(height: 12),
            _tile(
              context,
              icon: Icons.history_outlined,
              title: 'Activity',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ActivityScreen())),
            ),
            const SizedBox(height: 12),
            _tile(
              context,
              icon: Icons.hub_outlined,
              title: 'Behaviour Analysis',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BehaviourAnalysisScreen(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _tile(
              context,
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
            const SizedBox(height: 12),
            if (auth.isSuperAdmin) ...[
              _tile(
                context,
                icon: Icons.developer_mode_outlined,
                title: 'Developer Tools',
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const DebugScreen())),
              ),
              const SizedBox(height: 12),
            ],
            _tile(
              context,
              icon: Icons.info_outline,
              title: 'About',
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'SmartPoc',
                applicationVersion: '1.0.0',
              ),
            ),
            const SizedBox(height: 12),
            _tile(
              context,
              icon: Icons.logout,
              title: 'Log Out',
              color: AppColors.danger,
              onTap: () => auth.logout(),
            ),
          ],
        ),
      ),
    );
  }
}
