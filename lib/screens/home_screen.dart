import 'package:flutter/material.dart';
import 'package:vault_the_spire/services/identity_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final identity = IdentityService.instance.identity;

    return Scaffold(
      appBar: AppBar(
        title: const Text('VaultTheSpire'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome to VaultTheSpire',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Core identity and peer state are initialized.'),
            const SizedBox(height: 16),
            if (identity == null)
              const Text('Identity was not found. Please restart the app.')
            else ...[
              Text('Node ID: ${identity.nodeId}'),
              const SizedBox(height: 12),
              Text('Public Key (short): ${identity.publicKeyBase64.substring(0, 16)}...'),
              const SizedBox(height: 12),
              Text('Private Key (short): ${identity.privateKeyBase64.substring(0, 16)}...'),
            ],
            const SizedBox(height: 24),
            const Text('Next work: implement DHT + peer wire + torrents engine.'),
          ],
        ),
      ),
    );
  }
}
