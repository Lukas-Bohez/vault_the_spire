import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:vault_the_spire/constants.dart';
import 'package:vault_the_spire/services/ai_copilot_service.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:vault_the_spire/services/theme_service.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final SettingsService _settings;
  late final TextEditingController _ollamaUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _downloadDirController;
  late final TextEditingController _listenPortController;
  late final TextEditingController _maxGlobalController;
  late final TextEditingController _maxPerTorrentController;
  late final TextEditingController _maxActiveController;
  late final TextEditingController _downloadRateController;
  late final TextEditingController _uploadRateController;
  late AiCopilotService _aiService;

  List<String> _availableModels = <String>[];
  String? _selectedModel;
  bool _loadingModels = false;
  String _modelStatus = '';
  bool _savingNetwork = false;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _settings = SettingsService.instance;
    _ollamaUrlController = TextEditingController(
      text: _settings.aiOllamaUrl,
    );
    _modelController = TextEditingController(
      text: _settings.aiDefaultModel,
    );
    _downloadDirController = TextEditingController(
      text: _settings.downloadDestination,
    );
    _listenPortController = TextEditingController(text: '${_settings.listenPort}');
    _maxGlobalController = TextEditingController(
      text: '${_settings.maxConnectionsGlobal}',
    );
    _maxPerTorrentController = TextEditingController(
      text: '${_settings.maxConnectionsPerTorrent}',
    );
    _maxActiveController = TextEditingController(
      text: '${_settings.maxActiveDownloads}',
    );
    _downloadRateController = TextEditingController(
      text: '${_settings.downloadRateLimitKib}',
    );
    _uploadRateController = TextEditingController(
      text: '${_settings.uploadRateLimitKib}',
    );
    _selectedModel = _settings.aiDefaultModel;
    _themeMode = ThemeService.instance.themeMode;
    _aiService = AiCopilotService(
      baseUrl: _settings.aiOllamaUrl,
    );
    _fetchAvailableModels();
  }

  @override
  void dispose() {
    _ollamaUrlController.dispose();
    _modelController.dispose();
    _downloadDirController.dispose();
    _listenPortController.dispose();
    _maxGlobalController.dispose();
    _maxPerTorrentController.dispose();
    _maxActiveController.dispose();
    _downloadRateController.dispose();
    _uploadRateController.dispose();
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
    await _settings.setAiOllamaUrl(_ollamaUrlController.text);
    final modelToSave = _selectedModel ?? _modelController.text;
    await _settings.setAiDefaultModel(modelToSave);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('AI settings saved')));
  }

  Future<void> _pickDownloadDirectory() async {
    final chosen = await FilePicker.platform.getDirectoryPath();
    if (chosen == null || chosen.trim().isEmpty) return;
    _downloadDirController.text = chosen;
    await _settings.setDownloadDestination(chosen);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _saveNetworkSettings() async {
    setState(() {
      _savingNetwork = true;
    });
    try {
      final listenPort = int.tryParse(_listenPortController.text) ?? 6881;
      final maxGlobal = int.tryParse(_maxGlobalController.text) ?? 300;
      final maxPerTorrent = int.tryParse(_maxPerTorrentController.text) ?? 80;
      final maxActive = int.tryParse(_maxActiveController.text) ?? 3;
      final down = int.tryParse(_downloadRateController.text) ?? 0;
      final up = int.tryParse(_uploadRateController.text) ?? 0;

      await _settings.setListenPort(listenPort);
      await _settings.setMaxConnectionsGlobal(maxGlobal);
      await _settings.setMaxConnectionsPerTorrent(maxPerTorrent);
      await _settings.setMaxActiveDownloads(maxActive);
      await _settings.setDownloadRateLimitKib(down);
      await _settings.setUploadRateLimitKib(up);

      _listenPortController.text = '${_settings.listenPort}';
      _maxGlobalController.text = '${_settings.maxConnectionsGlobal}';
      _maxPerTorrentController.text = '${_settings.maxConnectionsPerTorrent}';
      _maxActiveController.text = '${_settings.maxActiveDownloads}';
      _downloadRateController.text = '${_settings.downloadRateLimitKib}';
      _uploadRateController.text = '${_settings.uploadRateLimitKib}';

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection settings saved')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _savingNetwork = false;
      });
    }
  }

  Future<void> _saveDownloadDestination() async {
    await _settings.setDownloadDestination(_downloadDirController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Download folder saved')),
    );
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    await ThemeService.instance.setThemeMode(mode);
    if (!mounted) return;
    setState(() {
      _themeMode = mode;
    });
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            _sectionCard(
              title: 'Downloads',
              children: [
                TextField(
                  controller: _downloadDirController,
                  decoration: const InputDecoration(
                    labelText: 'Default download folder',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickDownloadDirectory,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Browse'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _saveDownloadDestination,
                      child: const Text('Save Folder'),
                    ),
                  ],
                ),
                SwitchListTile(
                  title: const Text('Auto-start when added'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.autoStartOnAdd,
                  onChanged: (v) async {
                    await _settings.setAutoStartOnAdd(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Delete .torrent file when removing'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.deleteTorrentFileOnRemove,
                  onChanged: (v) async {
                    await _settings.setDeleteTorrentFileOnRemove(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Delete downloaded data when removing'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.deleteDataOnRemove,
                  onChanged: (v) async {
                    await _settings.setDeleteDataOnRemove(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            _sectionCard(
              title: 'Connection',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _listenPortController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Listen port',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _maxGlobalController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max global connections',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _maxPerTorrentController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max connections per torrent',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _maxActiveController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max active downloads',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _downloadRateController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Download rate limit (KiB/s, 0 = unlimited)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _uploadRateController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Upload rate limit (KiB/s, 0 = unlimited)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  title: const Text('Enable DHT'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.useDht,
                  onChanged: (v) async {
                    await _settings.setUseDht(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Enable Peer Exchange (PEX)'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.usePex,
                  onChanged: (v) async {
                    await _settings.setUsePex(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Enable Local Peer Discovery (LPD)'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.useLpd,
                  onChanged: (v) async {
                    await _settings.setUseLpd(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _savingNetwork ? null : _saveNetworkSettings,
                    child: Text(_savingNetwork ? 'Saving...' : 'Save Connection Settings'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _sectionCard(
              title: 'AI',
              children: [
                SwitchListTile(
                  title: const Text('Enable AI Copilot'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.enableAiCopilot,
                  onChanged: (v) async {
                    await _settings.setEnableAiCopilot(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Enable smart suggestions'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.enableSmartSuggestions,
                  onChanged: (v) async {
                    await _settings.setEnableSmartSuggestions(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
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
                    IconButton(
                      onPressed: _loadingModels ? null : _fetchAvailableModels,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh available models',
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _saveAiSettings,
                    child: const Text('Save AI Settings'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _sectionCard(
              title: 'Interface',
              children: [
                DropdownButtonFormField<ThemeMode>(
                  value: _themeMode,
                  decoration: const InputDecoration(
                    labelText: 'Theme',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('System'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Light'),
                    ),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _setThemeMode(value);
                  },
                ),
                SwitchListTile(
                  title: const Text('Enable sound effects'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.soundEffectsEnabled,
                  onChanged: (v) async {
                    await _settings.setSoundEffectsEnabled(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Use persistent sidebar'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.usePersistentSidebar,
                  onChanged: (v) async {
                    await _settings.setUsePersistentSidebar(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Use compact torrent rows'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.compactTorrentRows,
                  onChanged: (v) async {
                    await _settings.setCompactTorrentRows(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Confirm before exiting app'),
                  contentPadding: EdgeInsets.zero,
                  value: _settings.confirmOnExit,
                  onChanged: (v) async {
                    await _settings.setConfirmOnExit(v);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                  SwitchListTile(
                    title: const Text('Use system tray'),
                    contentPadding: EdgeInsets.zero,
                    value: _settings.useSystemTray,
                    onChanged: (v) async {
                      await _settings.setUseSystemTray(v);
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
                if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                  SwitchListTile(
                    title: const Text('Minimize to tray on close'),
                    contentPadding: EdgeInsets.zero,
                    value: _settings.minimizeToTrayOnClose,
                    onChanged: (v) async {
                      await _settings.setMinimizeToTrayOnClose(v);
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _sectionCard(
              title: 'About and Diagnostics',
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text('TorrentSpire AI'),
                  subtitle: Text('Torrent manager with built-in AI copilot'),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.calendar_month),
                  title: Text('App version'),
                  subtitle: Text('3.0.0+0'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.security),
                  title: const Text('Privacy policy'),
                  subtitle: Text(kPrivacyPolicyUrl),
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final now = DateTime.now().toIso8601String();
                        await _settings.setLastDiagnosticsExport(now);
                        if (!mounted) return;
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Diagnostics metadata updated'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.bug_report_outlined),
                      label: const Text('Mark Diagnostics Export'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        await _settings.clearBrowserHistory();
                        if (!mounted) return;
                        setState(() {});
                      },
                      child: const Text('Clear Browser History'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _settings.lastDiagnosticsExport.isEmpty
                      ? 'Last diagnostics export: never'
                      : 'Last diagnostics export: ${_settings.lastDiagnosticsExport}',
                ),
                const SizedBox(height: 10),
                const Text(
                  'Data Safety:\n'
                  '- No personal data collection\n'
                  '- No location data\n'
                  '- No identifiers shared\n'
                  '- No advertising or analytics',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
