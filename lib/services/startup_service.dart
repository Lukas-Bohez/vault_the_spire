import 'dart:io';

import 'package:path/path.dart' as p;

class StartupService {
  static Future<bool> enable() async {
    if (Platform.isWindows) {
      return _enableWindows();
    }
    if (Platform.isLinux) {
      return _enableLinux();
    }
    if (Platform.isMacOS) {
      // macOS autostart is unsupported in this helper.
      return false;
    }
    return false;
  }

  static Future<bool> disable() async {
    if (Platform.isWindows) {
      return _disableWindows();
    }
    if (Platform.isLinux) {
      return _disableLinux();
    }
    if (Platform.isMacOS) {
      return false;
    }
    return false;
  }

  static Future<bool> _enableWindows() async {
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return false;
      final startupDir = p.join(
        appData,
        'Microsoft',
        'Windows',
        'Start Menu',
        'Programs',
        'Startup',
      );
      final exePath = Platform.resolvedExecutable;
      final linkPath = p.join(startupDir, 'VaultTheSpire.lnk');
      final script =
          '''
\$w = New-Object -ComObject WScript.Shell
\$s = \$w.CreateShortcut("$linkPath")
\$s.TargetPath = "$exePath"
\$s.WorkingDirectory = "${p.dirname(exePath)}"
\$s.Save()
''';
      await Process.run('powershell', ['-NoProfile', '-Command', script]);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _disableWindows() async {
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return false;
      final linkPath = p.join(
        appData,
        'Microsoft',
        'Windows',
        'Start Menu',
        'Programs',
        'Startup',
        'VaultTheSpire.lnk',
      );
      final file = File(linkPath);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _enableLinux() async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null) return false;
      final autostartDir = p.join(home, '.config', 'autostart');
      await Directory(autostartDir).create(recursive: true);
      final desktopFile = p.join(autostartDir, 'vault_the_spire.desktop');
      final exePath = Platform.resolvedExecutable;
      final content =
          '''[Desktop Entry]
Type=Application
Name=VaultTheSpire
Exec=$exePath
X-GNOME-Autostart-enabled=true
''';
      await File(desktopFile).writeAsString(content);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _disableLinux() async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null) return false;
      final desktopFile = p.join(
        home,
        '.config',
        'autostart',
        'vault_the_spire.desktop',
      );
      final file = File(desktopFile);
      if (await file.exists()) await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
