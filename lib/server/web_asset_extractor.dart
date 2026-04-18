import 'dart:io';

import 'package:flutter/services.dart';

/// Extracts `assets/web_node/**` from the Flutter asset bundle into a
/// temporary filesystem directory so the shelf static handler can serve them.
///
/// Returns the directory path, or null if no web_node assets are bundled
/// (e.g. during development before running build_web_node.sh).
class WebAssetExtractor {
  static const _kPrefix = 'assets/web_node/';

  static Future<String?> extract() async {
    late AssetManifest manifest;
    try {
      manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    } catch (_) {
      return null;
    }

    final paths =
        manifest.listAssets().where((p) => p.startsWith(_kPrefix)).toList();
    if (paths.isEmpty) return null;

    final outDir =
        Directory('${Directory.systemTemp.path}/board_go_web_node');
    if (outDir.existsSync()) outDir.deleteSync(recursive: true);
    outDir.createSync(recursive: true);

    for (final assetPath in paths) {
      final data = await rootBundle.load(assetPath);
      final rel = assetPath.substring(_kPrefix.length);
      final file = File('${outDir.path}/$rel');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    }

    return outDir.path;
  }
}
