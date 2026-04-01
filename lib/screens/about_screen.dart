import 'package:flutter/material.dart';
import 'package:vault_the_spire/constants.dart';
import 'package:vault_the_spire/services/ai_copilot_service.dart';
import 'package:vault_the_spire/services/settings_service.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final TextEditingController _ollamaUrlController;
  late final TextEditingController _modelController;
  late AiCopilotService _aiService;
  
  List<String> _availableModels = <String>[];
  String? _selectedModel;
  bool _loadingModels = false;
  String _modelStatus = '';

  @override
  void initState() {
    super.initState();
    _ollamaUrlController = TextEditingController(
      text: SettingsService.instance.aiOllamaUrl,
    );
    _modelController = TextEditingController(
      text: SettingsService.instance.aiDefaultModel,
    );
    _selectedModel = SettingsService.instance.aiDefaultModel;
    _aiService = AiCopilotService(
      baseUrl: SettingsService.instance.aiOllamaUrl,
    );
    _fetchAvailableModels();
  }

  @override
  void dispose() {
    _ollamaUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _fetchAvailableModels() async {
    setState(() {
      _loadingModels = true;
      _modelStatus = 'Fetching models...';
    });

    try {
      final models = await _aiService.fetchModels();
      if (!mounted) return;
      setState(() {
        _availableModels = models;
        _loadingModels = false;
        if (models.isEmpty) {
          _modelStatus = 'No models available. Connect to Ollama first.';
        } else {
          _modelStatus = 'Successfully fetched ${models.length} model(s)';
          // Validate that the selected model exists
          if (!models.contains(_selectedModel)) {
            _selectedModel = models.first;
            _modelController.text = _selectedModel!;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _availableModels = <String>[];
        _loadingModels = false;
        _modelStatus = 'Failed to fetch models: $e';
      });
    }
  }

  Future<void> _onUrlChanged() async {
    final newUrl = _ollamaUrlController.text.trim();
    if (newUrl.isEmpty) return;

    _aiService.setBaseUrl(newUrl);
    await _fetchAvailableModels();
  }

  Future<void> _saveAiSettings() async {
    await SettingsService.instance.setAiOllamaUrl(_ollamaUrlController.text);
    final modelToSave = _selectedModel ?? _modelController.text;
    await SettingsService.instance.setAiDefaultModel(modelToSave);
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
              onChanged: (_) => _onUrlChanged(),
              decoration: const InputDecoration(
                labelText: 'Ollama Host URL',
                hintText: 'http://localhost:11434',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_availableModels.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: _selectedModel,
                          decoration: const InputDecoration(
                            labelText: 'Default AI Model',
                            border: OutlineInputBorder(),
                          ),
                          items: _availableModels
                              .map(
                                (model) => DropdownMenuItem<String>(
                                  value: model,
                                  child: Text(model),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedModel = value;
                              _modelController.text = value;
                            });
                          },
                        )
                      else
                        TextField(
                          controller: _modelController,
                          onChanged: (value) {
                            setState(() {
                              _selectedModel = value.isNotEmpty ? value : null;
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Default AI Model',
                            hintText: 'llama3',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        _modelStatus,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _modelStatus.contains('Failed') ? Colors.red : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: _loadingModels ? null : _fetchAvailableModels,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh available models',
                    ),
                  ],
                ),
              ],
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
