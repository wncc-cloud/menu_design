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
  // (self-order)" --project why-not-cafe-dev` (phase_plan/phase11_2.md
  // Console setup, done via CLI instead of the console UI — confirmed
  // real via `firebase apps:sdkconfig`). Real, non-secret value, same
  // as every other field below.
  static const String _webAppId = '1:809047549798:web:14b73a92d58a232d864aa7';

  // reCAPTCHA **Enterprise** site key ("Cafe Countryside Menu Self-
  // Order", created in the `why-not-cafe-dev` Google Cloud project's
  // reCAPTCHA Enterprise section — matching this app's Web App entry
  // there, not `cafe-countryside-menu`), registered against
  // cafe-countryside-menu.web.app. Classic reCAPTCHA v3 is no longer
  // registerable in Firebase App Check (Firebase's console disables the
  // classic secret-key field entirely, migration path closed since
  // early 2026) — Enterprise is the only option now. A site key is
  // meant to be public (embedded client-side on every page load), so
  // hardcoded as the real default the same way the fields below already
  // are — still overridable via
  // `--dart-define=POS_APP_CHECK_RECAPTCHA_SITE_KEY=...` if ever needed.
  static const String _recaptchaSiteKey = String.fromEnvironment(
    'POS_APP_CHECK_RECAPTCHA_SITE_KEY',
    defaultValue: '6LdTxpwtAAAAAJpIs6BSZeyK1JoeaNjwcjC2D3ap',
  );

  // apiKey/messagingSenderId/authDomain/storageBucket are shared by
  // every Web App registered under the same Firebase project — only
  // appId differs per registration — so these are the real, non-secret,
  // already-live `why-not-cafe-dev` values (Firebase web config isn't a
  // secret; matches billing_cafe's own
  // app/lib/config/firebase_options_pos.dart). Point this at
  // `why-not-cafe-prod`'s values (see that same file) once this app is
  // ready to go live against prod — no dev/prod flavor concept exists
  // in this project yet, so this is hardcoded to dev for now rather than
  // building one just for this.
  static const FirebaseOptions _devOptions = FirebaseOptions(
    apiKey: 'AIzaSyDaSu24dx-KnSQ7GDtuCtKQVrhwiLSOya0',
    appId: _webAppId,
    messagingSenderId: '809047549798',
    projectId: 'why-not-cafe-dev',
    authDomain: 'why-not-cafe-dev.firebaseapp.com',
    storageBucket: 'why-not-cafe-dev.firebasestorage.app',
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
      final posApp = await Firebase.initializeApp(name: 'appCheckOnly', options: _devOptions);
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
