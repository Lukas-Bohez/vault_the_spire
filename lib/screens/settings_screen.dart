import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:vault_the_spire/services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _displayNameController;
  late TextEditingController _downloadPathController;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: SettingsService.instance.displayName,
    );
    _downloadPathController = TextEditingController(
      text: SettingsService.instance.downloadDestination,
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _downloadPathController.dispose();
    super.dispose();
  }

  Future<void> _chooseDownloadPath() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      _downloadPathController.text = result;
      await SettingsService.instance.setDownloadDestination(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Default download path saved.')),
      );
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final displayName = _displayNameController.text.trim();
    await SettingsService.instance.setDisplayName(
      displayName.isEmpty ? 'Anonymous' : displayName,
    );

    final downloadPath = _downloadPathController.text.trim();
    if (downloadPath.isNotEmpty) {
      await SettingsService.instance.setDownloadDestination(downloadPath);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('User Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a display name or leave blank for Anonymous';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 24),
          const Text('Downloads', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _downloadPathController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Default Download Path',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _chooseDownloadPath,
                child: const Text('Browse...'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saveSettings,
        label: const Text('Save'),
        icon: const Icon(Icons.save),
      ),
    );
  }
}
