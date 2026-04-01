import 'package:flutter/material.dart';
import 'package:vault_the_spire/constants.dart';
import 'package:vault_the_spire/services/settings_service.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final TextEditingController _ollamaUrlController;
  late final TextEditingController _modelController;

  @override
  void initState() {
    super.initState();
    _ollamaUrlController = TextEditingController(
      text: SettingsService.instance.aiOllamaUrl,
    );
    _modelController = TextEditingController(
      text: SettingsService.instance.aiDefaultModel,
    );
  }

  @override
  void dispose() {
    _ollamaUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _saveAiSettings() async {
    await SettingsService.instance.setAiOllamaUrl(_ollamaUrlController.text);
    await SettingsService.instance.setAiDefaultModel(_modelController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('AI settings saved')));
  }

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
                  'AI Settings',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ollamaUrlController,
              decoration: const InputDecoration(
                labelText: 'Ollama Host URL',
                hintText: 'http://localhost:11434',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'Default AI Model',
                hintText: 'llama3',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _saveAiSettings,
                child: const Text('Save AI Settings'),
              ),
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
