import 'package:flutter/material.dart';
import 'package:vault_the_spire/screens/chat_hub_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VaultTheSpire Home')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.chat),
              label: const Text('Go to Chat'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChatHubScreen()),
                );
              },
            ),
            const SizedBox(height: 24),
            // Add more navigation buttons here as needed
            // ElevatedButton.icon(
            //   icon: Icon(Icons.settings),
            //   label: Text('Settings'),
            //   onPressed: () {},
            // ),
          ],
        ),
      ),
    );
  }
}
