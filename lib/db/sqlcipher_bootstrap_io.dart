import 'dart:io';

import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

Future<void> initSqlCipherOnAndroid() async {
  if (Platform.isAndroid) {
    await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
  }
}
