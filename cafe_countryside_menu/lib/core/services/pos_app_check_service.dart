// Firebase App Check for the POS (billing_cafe) project's Firestore
// (phase_plan/phase11_2.md in the billing_cafe repo). This app never
// reads/writes POS Firestore data directly — phase11_6.md's checkout
// flow talks to it over plain HTTPS (see phase11.md's "how the menu
// project talks to the POS project") — so this service exists purely to
// produce an `X-Firebase-AppCheck` token for those REST calls to attach.
//
// A minimal, read-nothing, write-nothing secondary Firebase app
// connection is still required because App Check's provider config is
// per registered Web App entry, not per project as a whole — this app's
// calls into the POS project need their own Web App registration (and
// their own reCAPTCHA Enterprise site key, scoped to this app's real
// domain), distinct from billing_cafe's own existing registration.
import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../logging/client_log.dart';

class PosAppCheckService {
  PosAppCheckService._();

  /// Local-testing-only escape hatch, same flag/spirit as
  /// `order_request_repository.dart`'s `useLocalEmulator` and
  /// `main.dart`'s `_useLocalEmulator` — routes this app's POS App
  /// Check activation (and, via `order_request_provider.dart`'s own
  /// matching flag, its REST calls) at the real `why-not-cafe-dev`
  /// cloud project instead of `why-not-cafe-prod`, so checkout can be
  /// exercised against dev's already-seeded data without ever touching
  /// prod. Defaults to `false` — omitting the flag (every real build)
  /// is byte-for-byte the same behavior as before this existed.
  static const _useDevPos = bool.fromEnvironment('USE_DEV_POS');

  // Registered via `firebase apps:create WEB "Cafe Countryside Menu
  // (self-order)" --project why-not-cafe-prod` (2026-08-29, mirrors the
  // dev registration this app used before — confirmed real via
  // `firebase apps:sdkconfig`). Real, non-secret value, same as every
  // other field below.
  static const String _webAppId = '1:871637263829:web:e123c297123dbbed5c495c';

  // reCAPTCHA **Enterprise** site key ("Cafe Countryside Menu Self-
  // Order", created in the `why-not-cafe-prod` Google Cloud project's
  // reCAPTCHA Enterprise section, mirroring the dev key's exact config
  // — SCORE integration, domains cafe-countryside-menu.web.app +
  // localhost), registered against cafe-countryside-menu.web.app (the
  // domain doesn't change between dev/prod, only the backend project
  // does). Classic reCAPTCHA v3 is no longer registerable in Firebase
  // App Check (Firebase's console disables the classic secret-key field
  // entirely, migration path closed since early 2026) — Enterprise is
  // the only option now. A site key is meant to be public (embedded
  // client-side on every page load), so hardcoded as the real default
  // the same way the fields below already are — still overridable via
  // `--dart-define=POS_APP_CHECK_RECAPTCHA_SITE_KEY=...` if ever needed.
  static const String _recaptchaSiteKey = String.fromEnvironment(
    'POS_APP_CHECK_RECAPTCHA_SITE_KEY',
    defaultValue: '6LfHvp0tAAAAAI4iRSJRK9ee9zBF7-JS3ALdl9sD',
  );

  // apiKey/messagingSenderId/authDomain/storageBucket are shared by
  // every Web App registered under the same Firebase project — only
  // appId differs per registration — so these are the real, non-secret,
  // already-live `why-not-cafe-prod` values (Firebase web config isn't a
  // secret; matches billing_cafe's own
  // app/lib/config/firebase_options_pos.dart's prod branch). No dev/prod
  // flavor concept exists in this project, so this is a plain hardcoded
  // swap (2026-08-29) — the prior dev values are recoverable from git
  // history if ever needed again.
  static const FirebaseOptions _posOptions = FirebaseOptions(
    apiKey: 'AIzaSyCi8WM2k2-HZBd_eS6gnI5ZjchA7DCztuE',
    appId: _webAppId,
    messagingSenderId: '871637263829',
    projectId: 'why-not-cafe-prod',
    authDomain: 'why-not-cafe-prod.firebaseapp.com',
    storageBucket: 'why-not-cafe-prod.firebasestorage.app',
  );

  // The pre-2026-08-29 `why-not-cafe-dev` values this project used
  // before the hardcoded prod swap above (recovered from git history,
  // commit 56a8aaa) — restored here behind `_useDevPos` rather than
  // just for one-off local testing against dev's seeded data.
  static const String _devWebAppId = '1:809047549798:web:14b73a92d58a232d864aa7';

  static const String _devRecaptchaSiteKey = '6LdTxpwtAAAAAJpIs6BSZeyK1JoeaNjwcjC2D3ap';

  static const FirebaseOptions _devOptions = FirebaseOptions(
    apiKey: 'AIzaSyDaSu24dx-KnSQ7GDtuCtKQVrhwiLSOya0',
    appId: _devWebAppId,
    messagingSenderId: '809047549798',
    projectId: 'why-not-cafe-dev',
    authDomain: 'why-not-cafe-dev.firebaseapp.com',
    storageBucket: 'why-not-cafe-dev.firebasestorage.app',
  );

  static FirebaseApp? _posApp;

  // Diagnostics only (Bug Logs): why getToken() had no token. Never changes behaviour.
  static final Stopwatch _sinceStart = Stopwatch();
  static String _activateState = 'not-started'; // not-started | pending | ok | failed | skipped
  static int? _activateMs;

  // Completes when activate() finishes (ok or failed). getToken() waits on it:
  // Bug Logs (2 Nov 2026) showed 163 of 192 token calls came while activation was
  // still pending (median 116 ms after start; activation takes ~1.2 s).
  static Completer<void>? _ready;
  static const _readyWait = Duration(seconds: 5);

  /// `activation=... activateMs=... sinceStartMs=...` text for log messages.
  static String get diagnostics =>
      'activation=$_activateState activateMs=${_activateMs ?? '-'} sinceStartMs=${_sinceStart.elapsedMilliseconds}';

  @visibleForTesting
  static void debugMarkPending() {
    _activateState = 'pending';
    _ready = Completer<void>();
  }

  @visibleForTesting
  static void debugFinish({required bool ok}) {
    _activateState = ok ? 'ok' : 'failed';
    _ready?.complete();
  }

  @visibleForTesting
  static void debugReset() {
    _posApp = null;
    _activateState = 'not-started';
    _activateMs = null;
    _ready = null;
    _sinceStart..stop()..reset();
  }

  /// Never throws — a blocked reCAPTCHA script, restrictive wifi, or a
  /// transient network failure here must never take down this app's
  /// launch (phase_plan/phase11_2.md). `phase11_6.md`'s checkout form
  /// still has to handle a missing/failed token gracefully at submit
  /// time regardless of whether this succeeds.
  ///
  /// This is `await`ed directly in `main()` before the app renders at
  /// all, so a hang here (not just a thrown error) would block the
  /// ENTIRE app's launch, not only self-order — worse than the
  /// `getToken()` hang phase11_7.md's live test actually caught. Same
  /// defensive timeout, since a different real network condition than
  /// the one tested could plausibly hang this specific call too.
  static Future<void> activate() async {
    final siteKey = _useDevPos ? _devRecaptchaSiteKey : _recaptchaSiteKey;
    if (siteKey.isEmpty) {
      _activateState = 'skipped';
      return;
    }
    _activateState = 'pending';
    final ready = _ready = Completer<void>();
    _sinceStart..reset()..start();
    try {
      final posApp = await Firebase.initializeApp(
        name: 'appCheckOnly',
        options: _useDevPos ? _devOptions : _posOptions,
      );
      await FirebaseAppCheck.instanceFor(app: posApp)
          .activate(providerWeb: ReCaptchaEnterpriseProvider(siteKey))
          .timeout(const Duration(seconds: 8));
      _posApp = posApp;
      _activateMs = _sinceStart.elapsedMilliseconds;
      _activateState = 'ok';
    } catch (e, st) {
      _activateMs = _sinceStart.elapsedMilliseconds;
      _activateState = 'failed';
      debugPrint('[PosAppCheckService] activation failed: $e\n$st');
      logClientWarn('PosAppCheck.activate', e,
          stackTrace: st, message: '$e [$diagnostics]');
    } finally {
      if (!ready.isCompleted) ready.complete();
    }
  }

  /// A fresh App Check token for the POS project, for
  /// `phase11_6.md`'s REST calls to attach as the
  /// `X-Firebase-AppCheck` header — null if activation never
  /// succeeded (unconfigured, or activate() failed), so callers can
  /// fall back to submitting without a token rather than crash.
  ///
  /// DIAGNOSTIC (2026-08-28, phase11_7.md's "App Check failure doesn't
  /// block the app" full-stack check): a real live test with the
  /// reCAPTCHA domain blocked showed the checkout button spinning
  /// indefinitely instead of surfacing the intended fallback message —
  /// the underlying JS SDK call has no timeout of its own, so a
  /// silently-dropped-packets style block (corporate firewall, some ad
  /// blockers) hangs this `await` forever rather than failing fast.
  /// The 8-second timeout below is what actually makes the "never
  /// blocks the app" guarantee true under a real network failure, not
  /// just a thrown-exception one.
  static Future<String?> getToken() async {
    final total = Stopwatch()..start();
    if (_posApp == null && _activateState == 'pending') {
      // Activation is still running: wait for it (bounded) instead of giving up.
      try {
        await _ready?.future.timeout(_readyWait);
      } on TimeoutException {
        // fall through: logged below as "still pending"
      }
    }
    final app = _posApp;
    if (app == null) {
      // Used to return silently, so "Self-ordering isn't available" had no
      // matching log. Say why: activation still pending (race), failed, or skipped.
      logClientWarn('PosAppCheck.getToken', 'no token: App Check not active',
          message: 'no token: App Check not active [$diagnostics]');
      return null;
    }
    final t = Stopwatch()..start();
    // One shared deadline: time already spent waiting for activation comes off the
    // 8 s token timeout (but never below 3 s), so the whole call stays near 8 s.
    final left = const Duration(seconds: 8) - total.elapsed;
    final tokenTimeout = left < const Duration(seconds: 3) ? const Duration(seconds: 3) : left;
    try {
      return await FirebaseAppCheck.instanceFor(app: app)
          .getToken()
          .timeout(tokenTimeout);
    } catch (e, st) {
      debugPrint('[PosAppCheckService] getToken failed: $e\n$st');
      logClientWarn('PosAppCheck.getToken', e,
          stackTrace: st, message: '$e [getTokenMs=${t.elapsedMilliseconds} $diagnostics]');
      return null;
    }
  }
}
