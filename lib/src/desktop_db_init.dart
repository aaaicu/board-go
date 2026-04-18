import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void initDesktopDatabase() {
  if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
