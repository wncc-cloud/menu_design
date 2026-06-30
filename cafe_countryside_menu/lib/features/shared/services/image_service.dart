import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

class ImageService {
  /// Compresses [bytes] to ≤150 KB at ≤800×800 px in JPEG format.
  /// Uses compressWithList — the only method compatible with Flutter Web.
  Future<Uint8List> compress(Uint8List bytes) async {
    return FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 800,
      minHeight: 800,
      quality: 82,
      format: CompressFormat.jpeg,
    );
  }
}
