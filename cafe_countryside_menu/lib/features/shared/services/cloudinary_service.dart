import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';

class CloudinaryUploadResult {
  final String secureUrl;
  final String publicId;

  const CloudinaryUploadResult({
    required this.secureUrl,
    required this.publicId,
  });
}

class CloudinaryService {
  Future<CloudinaryUploadResult> upload({
    required Uint8List bytes,
    required String publicId,
  }) async {
    final uri = Uri.parse(AppConstants.cloudinaryUploadUrl);

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = AppConstants.cloudinaryUploadPreset
      ..fields['public_id'] = publicId
      // overwrite is NOT sent — unsigned presets forbid it.
      // Callers must include a timestamp in publicId to guarantee uniqueness.
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: 'image.jpg',
      ));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception(
          'Cloudinary upload failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return CloudinaryUploadResult(
      secureUrl: json['secure_url'] as String,
      publicId: json['public_id'] as String,
    );
  }
}
