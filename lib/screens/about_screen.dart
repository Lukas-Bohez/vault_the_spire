import 'package:flutter/material.dart';
import 'package:vault_the_spire/constants.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About VaultTheSpire')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('VaultTheSpire'),
              subtitle: Text('Secure local vault + encrypted P2P file sharing'),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text('App version'),
              subtitle: const Text('3.0.0+0'),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.security),
              title: const Text('Privacy policy'),
              subtitle: Text(kPrivacyPolicyUrl),
            ),
            const SizedBox(height: 8),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  'Data Safety (Play Store):\n'
                  '- No personal data collection\n'
                  '- No location data\n'
                  '- No identifiers shared\n'
                  '- No advertising or analytics',
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Notes:\n'
              '- Permissions are only requested when needed for explicit user actions.\n'
              '- All data is encrypted locally with user passphrase.\n'
              '- P2P connections are user-initiated and optionally managed through server invite codes.',
            ),
          ],
        ),
      ),
    );
  }
}
