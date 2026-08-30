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
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class PosAppCheckService {
  PosAppCheckService._();

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

  static FirebaseApp? _posApp;

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
    if (_recaptchaSiteKey.isEmpty) {
      return;
    }
    try {
      final posApp = await Firebase.initializeApp(name: 'appCheckOnly', options: _posOptions);
      await FirebaseAppCheck.instanceFor(app: posApp)
          .activate(providerWeb: ReCaptchaEnterpriseProvider(_recaptchaSiteKey))
          .timeout(const Duration(seconds: 8));
      _posApp = posApp;
    } catch (e, st) {
      debugPrint('[PosAppCheckService] activation failed: $e\n$st');
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
    final app = _posApp;
    if (app == null) return null;
    try {
      return await FirebaseAppCheck.instanceFor(app: app)
          .getToken()
          .timeout(const Duration(seconds: 8));
    } catch (e, st) {
      debugPrint('[PosAppCheckService] getToken failed: $e\n$st');
      return null;
    }
  }
}
