import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'auth/auth_provider.dart';
import 'gmail_sync_dialog.dart';
import 'particle_background.dart';
import 'session/session_provider.dart';
import 'auth/enroll_voice_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _row(
    BuildContext context, {
    required String title,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final email = context.watch<AuthProvider>().email;
    final session = context.read<SessionProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ParticleBackground(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _row(
              context,
              title: 'Wake word ("Hey Myna")',
              trailing: Switch(
                value: settings.wakeWordEnabled,
                onChanged: (value) async {
                  if (!value) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const EnrollVoiceScreen()),
                    );
                  }
                  await settings.setWakeWordEnabled(value);
                  if (session.state.isConnected) {
                    await session.interactionEngineClient.setWakeWordEnabled(
                      value,
                    );
                  }
                },
              ),
            ),
            if (!settings.wakeWordEnabled) ...[
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EnrollVoiceScreen()),
                ),
                child: _row(
                  context,
                  title: 'Enroll / Manage Voice Profile',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Setup Voice',
                        style: TextStyle(
                          color: AppColors.accentStrong,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        color: AppColors.accentStrong,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _row(
              context,
              title: 'Dark mode',
              trailing: Switch(
                value: settings.isDarkMode,
                onChanged: (value) => settings.setDarkMode(value),
              ),
            ),
            const SizedBox(height: 12),
            _row(
              context,
              title: 'Connected account',
              trailing: Text(
                email.isEmpty ? '—' : email,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => showDialog(
                context: context,
                builder: (_) => const GmailSyncDialog(),
              ),
              child: _row(
                context,
                title: 'Sync Gmail',
                trailing: Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
