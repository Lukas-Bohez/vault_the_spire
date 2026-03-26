import 'package:flutter/material.dart';
import 'package:vault_the_spire/screens/dm_screen.dart';
import 'package:vault_the_spire/services/settings_service.dart';

class ChatHubScreen extends StatefulWidget {
  const ChatHubScreen({super.key});

  @override
  State<ChatHubScreen> createState() => _ChatHubScreenState();
}

class _ChatHubScreenState extends State<ChatHubScreen> {
  final _peerController = TextEditingController();
  String _user = SettingsService.instance.displayName;
  String? _activePeer;

  @override
  void dispose() {
    _peerController.dispose();
    super.dispose();
  }

  void _startDm() {
    final peer = _peerController.text.trim();
    if (peer.isEmpty) return;
    setState(() {
      _activePeer = peer;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_activePeer != null && _activePeer!.isNotEmpty) {
      return DMScreen(user: _user, peer: _activePeer!);
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('2. Direct Peer Chat', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Your identity: $_user', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _peerController,
            decoration: const InputDecoration(
              labelText: 'Peer username',
              hintText: 'Enter a username to connect',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _startDm(),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _startDm,
            child: const Text('Connect to Peer'),
          ),
          const SizedBox(height: 12),
          const Text('Enter a peer username and press connect to open a direct P2P chat.'),
        ],
      ),
    );
  }
}
