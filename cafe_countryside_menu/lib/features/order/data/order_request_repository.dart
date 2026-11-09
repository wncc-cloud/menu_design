// phase_plan/phase11_5.md (billing_cafe repo) — plain-http REST client
// for the POS project's businesses/{businessId}/customerOrderRequests
// collection (phase_plan/phase11.md's decision 7: option B, no
// cloud_firestore dependency in this project for this feature). Every
// call attaches an X-Firebase-AppCheck token from PosAppCheckService.
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../../core/services/pos_app_check_service.dart';
import '../../../core/logging/client_log.dart';

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

  /// Local-testing-only escape hatch (`--dart-define=USE_FIREBASE_EMULATOR=true`,
  /// same flag name billing_cafe's own `env.dart` already uses for this
  /// exact purpose) — routes every REST call at the local Firestore
  /// emulator (`firebase/dev-seed`'s `demo-why-not-cafe` project,
  /// matching `seed.js`'s own project id) instead of [posProjectId], and
  /// skips requiring a real App Check token (the emulator's REST
  /// surface never verifies one). **Never true in a real build** — no
  /// dart-define means this defaults to false and every real user still
  /// goes through the exact same real-project path as before this flag
  /// existed.
  final bool useLocalEmulator;

  /// Tests inject a fake client; real builds leave it null (plain `http`).
  final http.Client? client;

  /// Wait before the single network-drop retry (tests pass zero).
  final Duration retryDelay;

  const OrderRequestRepository({
    required this.posProjectId,
    required this.posWebApiKey,
    required this.businessId,
    this.useLocalEmulator = false,
    this.client,
    this.retryDelay = const Duration(milliseconds: 1500),
  });

  /// Phone clock this far from the server's clock counts as "wrong clock".
  static const clockSkewThreshold = Duration(seconds: 20);

  /// Server minus phone clock, from the newest `Date` header seen. Free: it
  /// rides on replies the app already gets. Null until one has been seen.
  static Duration? lastServerOffset;

  static void _rememberServerOffset(http.Response r) {
    final o = serverOffsetOf(r);
    if (o != null) lastServerOffset = o;
  }

  static const _emulatorBase =
      'http://127.0.0.1:8080/v1/projects/demo-why-not-cafe/databases/(default)/documents';

  Uri get _collectionUri => Uri.parse(
        useLocalEmulator
            ? '$_emulatorBase/businesses/$businessId/customerOrderRequests'
            : 'https://firestore.googleapis.com/v1/projects/$posProjectId/databases/(default)/'
                'documents/businesses/$businessId/customerOrderRequests?key=$posWebApiKey',
      );

  Uri _documentUri(String requestId) => Uri.parse(
        useLocalEmulator
            ? '$_emulatorBase/businesses/$businessId/customerOrderRequests/$requestId'
            : 'https://firestore.googleapis.com/v1/projects/$posProjectId/databases/(default)/'
                'documents/businesses/$businessId/customerOrderRequests/$requestId?key=$posWebApiKey',
      );

  Future<String> _requireToken() async {
    if (useLocalEmulator) return 'local-emulator-test-token';
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
  ///
  /// Safe-retry design (adds no cost in the normal case — one request, as
  /// before):
  /// * The phone picks the document id (`?documentId=`), so a repeat of the
  ///   same request can never create a second order.
  /// * ONE retry, only after a network drop ("Load failed" / "Failed to
  ///   fetch"), or after a 403 caused by a wrong phone clock (the café's rule
  ///   needs `expiresAt` within 30 min of the SERVER time; the retry uses
  ///   times shifted by the server's own `Date` header).
  /// * If the retry is refused because the first try already landed (409, or
  ///   403 from the rules seeing an existing doc), a public GET of our own id
  ///   confirms it and the order counts as placed.
  /// Every failure is logged once, with the whole story (see [describeRestFailure]).
  Future<String> createRequest(Map<String, dynamic> data) async {
    final token = await _requireToken();
    final id = newRequestId();
    final story = <String>[]; // what happened on each attempt, for the Bug Log
    var body = data;
    var afterNetworkDrop = false;

    for (var attempt = 1; attempt <= 2; attempt++) {
      final http.Response response;
      try {
        response = await _post(
          _createUri(id),
          {'X-Firebase-AppCheck': token, 'Content-Type': 'application/json'},
          jsonEncode(_encodeFields(body)),
        );
      } catch (e, st) {
        story.add('attempt$attempt: ${_shortError(e)}');
        if (attempt == 1) {
          afterNetworkDrop = true;
          await Future<void>.delayed(retryDelay);
          continue;
        }
        // Both tries dropped. The first might still have landed: ask.
        if (await _existsQuietly(id)) {
          _logRecovered(story, id);
          return id;
        }
        // _shortError: the raw exception text carries the URL (API key + the order id).
        logClientError('OrderRequest.create', _shortError(e),
            stackTrace: st, message: _failureMessage(story, 'network error', data));
        throw const OrderRequestException('Could not place your order — check your connection and try again.');
      }

      _rememberServerOffset(response);
      if (response.statusCode == 200) {
        if (attempt == 2) _logRecovered(story, id);
        return id;
      }

      story.add('attempt$attempt: ${describeRestFailure(response)}');
      if (attempt == 2 && afterNetworkDrop && (response.statusCode == 409 || response.statusCode == 403)) {
        // "Already exists": the first try did land.
        if (await _existsQuietly(id)) {
          _logRecovered(story, id);
          return id;
        }
      }
      final skew = response.statusCode == 403 ? serverOffsetOf(response) : null;
      if (attempt == 1 && skew != null && skew.abs() >= clockSkewThreshold) {
        body = shiftRequestTimes(body, skew);
        story.add('clockOffsetSec=${skew.inSeconds} -> retrying with server time');
        continue;
      }
      break;
    }

    logClientError('OrderRequest.create', 'HTTP rejected',
        message: _failureMessage(story, 'rejected', data));
    throw const OrderRequestException('Could not place your order — check your connection and try again.');
  }

  /// The 20-character random id the phone gives its order (same alphabet and
  /// length as Firestore's own auto ids; secure random so it cannot be guessed,
  /// because anyone who knows an id can read that order).
  static String newRequestId([Random? random]) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final r = random ?? Random.secure();
    return String.fromCharCodes(List.generate(20, (_) => alphabet.codeUnitAt(r.nextInt(alphabet.length))));
  }

  Uri _createUri(String id) {
    final base = _collectionUri;
    return base.replace(queryParameters: {...base.queryParameters, 'documentId': id});
  }

  /// Plain `http` unless a test injects a client.
  Future<http.Response> _post(Uri uri, Map<String, String> headers, String body) =>
      client != null ? client!.post(uri, headers: headers, body: body) : http.post(uri, headers: headers, body: body);

  Future<http.Response> _get(Uri uri, Map<String, String> headers) =>
      client != null ? client!.get(uri, headers: headers) : http.get(uri, headers: headers);

  /// True when our own order id can be read back. Never throws, never logs.
  Future<bool> _existsQuietly(String id) async {
    try {
      final token = useLocalEmulator ? 'local-emulator-test-token' : await PosAppCheckService.getToken();
      if (token == null) return false;
      final r = await _get(_documentUri(id), {'X-Firebase-AppCheck': token});
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// One WARN saying a retry saved the order (so we can see how often the
  /// retry matters). Same source as the errors: no new rules entry needed.
  void _logRecovered(List<String> story, String id) {
    logClientWarn('OrderRequest.create', 'recovered by retry',
        message: 'Order placed after a retry (no customer-visible error) [${story.join(' | ')}]');
  }

  /// Builds the one ERROR line: what failed, each attempt, the sizes of the fields the café's rule limits (lengths only, never the text),
  /// and the phone-vs-server clock difference.
  String _failureMessage(List<String> story, String what, Map<String, dynamic> data) {
    final offset = lastServerOffset;
    final text = 'Order request $what [${story.join(' | ')}] '
        '[clockOffsetSec=${offset == null ? 'unknown' : offset.inSeconds} shape: ${describeRequestShape(data)}]';
    return text;
  }

  Uri get _cafeStatusUri => Uri.parse(
        useLocalEmulator
            ? '$_emulatorBase/businesses/$businessId/public/cafeStatus'
            : 'https://firestore.googleapis.com/v1/projects/$posProjectId/databases/(default)/'
                'documents/businesses/$businessId/public/cafeStatus?key=$posWebApiKey',
      );

  /// billing_cafe phase12.md §12.3-B — reads `public/cafeStatus.open`.
  /// Returns `null` (UNKNOWN — callers treat as open) for anything other
  /// than a clear boolean: not published yet (404), no App Check token, a
  /// timeout, a non-200 or a malformed body. Never throws.
  Future<bool?> fetchCafeOpen({Duration timeout = const Duration(seconds: 6)}) async {
    try {
      final token = await _requireToken();
      final response = await _get(_cafeStatusUri, {'X-Firebase-AppCheck': token}).timeout(timeout);
      _rememberServerOffset(response);
      if (response.statusCode != 200) {
        // 404 = "not published yet": normal. Anything else used to vanish
        // silently; now the reason (e.g. App Check refused) reaches Bug Logs.
        if (response.statusCode != 404) {
          logClientWarn('OrderRequest.fetchCafeOpen', 'HTTP ${response.statusCode}',
              message: 'Cafe status read refused: ${describeRestFailure(response)}');
        }
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final fields = json['fields'] as Map<String, dynamic>?;
      final open = fields?['open'] as Map<String, dynamic>?;
      final value = open?['booleanValue'];
      return value is bool ? value : null;
    } catch (e, st) {
      logClientWarn('OrderRequest.fetchCafeOpen', e, stackTrace: st);
      return null;
    }
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
      response = await _get(_documentUri(requestId), {'X-Firebase-AppCheck': token});
    } catch (e, st) {
      logClientWarn('OrderRequest.getRequest', e, stackTrace: st);
      throw const OrderRequestException('Could not check your order status right now.');
    }
    _rememberServerOffset(response);

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      // The order document is publicly readable, so a 403 here means App
      // Check (or the rules) refused: say so in the log instead of hiding it.
      logClientWarn('OrderRequest.getRequest', 'HTTP ${response.statusCode}',
          message: 'Order status read refused: ${describeRestFailure(response)}');
      if (response.statusCode == 403) return null;
      throw const OrderRequestException('Could not check your order status right now.');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final fields = json['fields'] as Map<String, dynamic>?;
    if (fields == null) return null;
    return _decodeFields(fields);
  }
}

// ---- Bug Log diagnostics (pure functions, unit-tested) ----

String _shortError(Object e) {
  final s = e.toString();
  // The URL carries the public API key and our order id: keep only the reason.
  final cut = s.indexOf(', uri=');
  final t = cut > 0 ? s.substring(0, cut) : s;
  return t.length > 80 ? t.substring(0, 80) : t;
}

/// One short line about a non-200 reply: `HTTP 403 PERMISSION_DENIED "Missing
/// or insufficient permissions." serverDate=(the reply's Date header)`. Reads Firestore's JSON
/// error body (`{"error": {"status", "message"}}`). Never throws; an unreadable
/// body just leaves those parts out. No tokens, no customer text.
String describeRestFailure(http.Response r) {
  var status = '';
  var message = '';
  try {
    final decoded = jsonDecode(r.body);
    final err = decoded is Map ? decoded['error'] : (decoded is List && decoded.isNotEmpty && decoded.first is Map ? (decoded.first as Map)['error'] : null);
    if (err is Map) {
      status = '${err['status'] ?? ''}';
      message = '${err['message'] ?? ''}';
    }
  } catch (_) {}
  if (message.length > 160) message = message.substring(0, 160);
  final date = r.headers['date'];
  return 'HTTP ${r.statusCode}'
      '${status.isEmpty ? '' : ' $status'}'
      '${message.isEmpty ? '' : ' "$message"'}'
      '${date == null ? '' : ' serverDate=$date'}';
}

/// Server time minus phone time, from the reply's `Date` header (1 s
/// resolution, minus the reply's travel time: fine for a 20 s threshold).
/// Null when the header is missing or unreadable.
Duration? serverOffsetOf(http.Response r, {DateTime? deviceNow}) {
  final raw = r.headers['date'];
  if (raw == null) return null;
  final server = parseHttpDate(raw);
  return server?.difference((deviceNow ?? DateTime.now()).toUtc());
}

/// Parses `Mon, 09 Nov 2026 11:10:37 GMT`. Null if it does not match.
DateTime? parseHttpDate(String s) {
  final m = RegExp(r'^\w{3}, (\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$').firstMatch(s.trim());
  if (m == null) return null;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final month = months.indexOf(m.group(2)!);
  if (month < 0) return null;
  return DateTime.utc(int.parse(m.group(3)!), month + 1, int.parse(m.group(1)!), int.parse(m.group(4)!),
      int.parse(m.group(5)!), int.parse(m.group(6)!));
}

/// Copy of [data] with `createdAt` / `expiresAt` moved by [by], so the café's
/// "expiresAt within 30 min of server time" rule is judged on server time.
Map<String, dynamic> shiftRequestTimes(Map<String, dynamic> data, Duration by) {
  final copy = Map<String, dynamic>.of(data);
  for (final k in const ['createdAt', 'expiresAt']) {
    final v = copy[k];
    if (v is DateTime) copy[k] = v.add(by);
  }
  return copy;
}

/// Field SIZES the café's rule limits (lines <= 30, name <= 60, phone <= 20,
/// table <= 20, notes <= 300), plus the order's lifetime. Numbers only, so a
/// rule refusal can be told apart from a wrong clock without storing any
/// customer text.
String describeRequestShape(Map<String, dynamic> d) {
  int len(String k) => d[k] is String ? (d[k] as String).length : -1;
  final lines = d['lines'];
  final created = d['createdAt'];
  final expires = d['expiresAt'];
  final life = created is DateTime && expires is DateTime ? expires.difference(created).inSeconds : null;
  return 'lines=${lines is List ? lines.length : -1} name=${len('customerName')} phone=${len('customerPhone')} '
      'table=${len('tableNumber')} notes=${len('orderNotes')} lifeSec=${life ?? -1}';
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
