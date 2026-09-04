// phase_plan/phase11_5.md (billing_cafe repo) — plain-http REST client
// for the POS project's businesses/{businessId}/customerOrderRequests
// collection (phase_plan/phase11.md's decision 7: option B, no
// cloud_firestore dependency in this project for this feature). Every
// call attaches an X-Firebase-AppCheck token from PosAppCheckService.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/services/pos_app_check_service.dart';

/// Thrown when no App Check token could be obtained — a real, expected
/// failure mode (the device's browser/network genuinely blocking
/// reCAPTCHA, e.g. an ad-blocker or restrictive wifi — see
/// phase_plan/phase11_2.md's "Honest trade-off" note), not a crash.
/// phase_plan/phase11_6.md's checkout form shows a specific, non-retry
/// "tell the cashier directly" message for exactly this exception —
/// never a generic error.
class AppCheckTokenException implements Exception {
  final String message;
  const AppCheckTokenException(this.message);
  @override
  String toString() => message;
}

/// Thrown for any other failure — network error, timeout, an
/// unexpected non-2xx response. Unlike [AppCheckTokenException], this
/// IS retry-able (phase_plan/phase11_6.md's checkout form re-enables
/// its submit button and shows a "check your connection" message for
/// this one, distinctly from the App Check case).
class OrderRequestException implements Exception {
  final String message;
  const OrderRequestException(this.message);
  @override
  String toString() => message;
}

class OrderRequestRepository {
  final String posProjectId;
  final String posWebApiKey;
  final String businessId;

  const OrderRequestRepository({
    required this.posProjectId,
    required this.posWebApiKey,
    required this.businessId,
  });

  Uri get _collectionUri => Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$posProjectId/databases/(default)/'
        'documents/businesses/$businessId/customerOrderRequests?key=$posWebApiKey',
      );

  Uri _documentUri(String requestId) => Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$posProjectId/databases/(default)/'
        'documents/businesses/$businessId/customerOrderRequests/$requestId?key=$posWebApiKey',
      );

  Future<String> _requireToken() async {
    final token = await PosAppCheckService.getToken();
    if (token == null) {
      throw const AppCheckTokenException(
        "Self-ordering isn't available on this device right now — "
        'please tell the cashier your order directly at the counter.',
      );
    }
    return token;
  }

  /// Creates a new `customerOrderRequests` document. [data] is a plain
  /// Dart map matching phase_plan/phase11.md's Data model exactly (no
  /// `requestId`/`businessDate`/`orderType` keys — see that section's
  /// "why these are excluded" notes); this method encodes it into the
  /// Firestore REST API's typed-value envelope. Returns the new
  /// document's id (parsed from the response's `name` path).
  Future<String> createRequest(Map<String, dynamic> data) async {
    final token = await _requireToken();

    final http.Response response;
    try {
      response = await http.post(
        _collectionUri,
        headers: {'X-Firebase-AppCheck': token, 'Content-Type': 'application/json'},
        body: jsonEncode(_encodeFields(data)),
      );
    } catch (e) {
      throw OrderRequestException('Could not place your order — check your connection and try again.');
    }

    if (response.statusCode != 200) {
      throw OrderRequestException('Could not place your order — check your connection and try again.');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final name = json['name'] as String?;
    if (name == null) {
      throw const OrderRequestException('Your order may not have been saved — please try again.');
    }
    return name.split('/').last;
  }

  /// Reads back a request's current fields — used by the order-status
  /// page's poll loop to watch for `linkedOrderNumber` appearing. Never
  /// throws for a not-found/inaccessible document (returns `null`
  /// instead) since a single failed lookup shouldn't be indistinguishable
  /// from a real error to the caller's retry logic; a genuine network/
  /// App-Check failure still throws, same as [createRequest].
  Future<Map<String, dynamic>?> getRequest(String requestId) async {
    final token = await _requireToken();

    final http.Response response;
    try {
      response = await http.get(_documentUri(requestId), headers: {'X-Firebase-AppCheck': token});
    } catch (e) {
      throw const OrderRequestException('Could not check your order status right now.');
    }

    if (response.statusCode == 404 || response.statusCode == 403) {
      return null;
    }
    if (response.statusCode != 200) {
      throw const OrderRequestException('Could not check your order status right now.');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final fields = json['fields'] as Map<String, dynamic>?;
    if (fields == null) return null;
    return _decodeFields(fields);
  }
}

// ---- Firestore REST API typed-value envelope encoding/decoding ----
// Every field value is wrapped ({"stringValue": "..."},
// {"integerValue": "..."}, {"arrayValue": {"values": [...]}}, etc.) —
// meaningfully more boilerplate than the Firestore SDK, and easy to
// get subtly wrong for nested shapes (an array of maps, this
// collection's `lines[]`, is the trickiest case: each element needs
// its own `mapValue: {fields: {...}}`). Given its own unit tests
// (test/order_request_repository_test.dart) rather than only exercised
// indirectly via a real network call.

Map<String, dynamic> _encodeFields(Map<String, dynamic> data) {
  return {'fields': data.map((key, value) => MapEntry(key, encodeFirestoreValue(value)))};
}

Map<String, dynamic> _decodeFields(Map<String, dynamic> fields) {
  return fields.map((key, value) => MapEntry(key, decodeFirestoreValue(value as Map<String, dynamic>)));
}

/// Exposed (not private) so its own unit tests can exercise every
/// value shape directly, independent of a real HTTP round-trip.
Map<String, dynamic> encodeFirestoreValue(dynamic value) {
  if (value == null) return {'nullValue': null};
  if (value is String) return {'stringValue': value};
  if (value is bool) return {'booleanValue': value};
  if (value is int) return {'integerValue': value.toString()};
  if (value is double) return {'doubleValue': value};
  if (value is DateTime) {
    // phase_plan/phase11_5.md — a plain client-computed literal, not a
    // server-value transform (the plain createDocument call has no way
    // to request one); safe since createdAt/expiresAt are never
    // checked by a Security Rule for correctness, only bounded
    // (expiresAt) or displayed (createdAt).
    return {'timestampValue': value.toUtc().toIso8601String()};
  }
  if (value is List) {
    return {
      'arrayValue': {'values': value.map(encodeFirestoreValue).toList()},
    };
  }
  if (value is Map) {
    return {
      'mapValue': {
        'fields': value.map((key, v) => MapEntry(key as String, encodeFirestoreValue(v))),
      },
    };
  }
  throw ArgumentError('Unsupported type for Firestore REST encoding: ${value.runtimeType}');
}

/// Exposed for the same reason as [encodeFirestoreValue].
dynamic decodeFirestoreValue(Map<String, dynamic> value) {
  if (value.containsKey('nullValue')) return null;
  if (value.containsKey('stringValue')) return value['stringValue'] as String;
  if (value.containsKey('booleanValue')) return value['booleanValue'] as bool;
  if (value.containsKey('integerValue')) return int.parse(value['integerValue'] as String);
  if (value.containsKey('doubleValue')) return (value['doubleValue'] as num).toDouble();
  if (value.containsKey('timestampValue')) return DateTime.parse(value['timestampValue'] as String);
  if (value.containsKey('arrayValue')) {
    final arrayValue = value['arrayValue'] as Map<String, dynamic>;
    final values = arrayValue['values'] as List<dynamic>?;
    return (values ?? const []).map((v) => decodeFirestoreValue(v as Map<String, dynamic>)).toList();
  }
  if (value.containsKey('mapValue')) {
    final mapValue = value['mapValue'] as Map<String, dynamic>;
    final fields = mapValue['fields'] as Map<String, dynamic>?;
    return _decodeFields(fields ?? const {});
  }
  return null;
}
