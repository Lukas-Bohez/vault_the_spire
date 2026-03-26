Set-Location 'c:\flutter\vault_the_spire'
$text = @'
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isDark = false;

  void _toggleTheme() {
    setState(() {
      _isDark = !_isDark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('VaultTheSpire'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Home Screen loaded successfully.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _toggleTheme,
                child: Text(_isDark ? 'Switch to Light' : 'Switch to Dark'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
'@
Set-Content -Path 'lib\screens\home_screen.dart' -Value $text -Encoding UTF8
