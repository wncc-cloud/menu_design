import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/services/pos_app_check_service.dart';
import 'firebase_options.dart';
import 'router.dart';

/// Local-testing-only escape hatch, same flag/spirit as
/// `order_request_provider.dart`'s own `_useLocalEmulator` (which only
/// covers the POS project's `customerOrderRequests` REST calls) — this
/// one redirects THIS project's own `FirebaseFirestore.instance` (menu,
/// business settings, sections — everything `menu_repository.dart`/
/// `business_repository.dart`/etc. read) at the local Firestore
/// emulator described in billing_cafe's `firebase/dev-seed/
/// menu-emulator/` (port 8081, project `why-not-cafe-menu-dev`),
/// instead of the real `cafe-countryside-menu` project. Never true in a
/// real build — no dart-define means this defaults to false.
const _useLocalEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');

/// A Firestore emulator instance namespaces data by project id — just
/// pointing `useFirestoreEmulator` at localhost:8081 while keeping the
/// real `cafe-countryside-menu` project id still reads an empty
/// "cafe-countryside-menu" namespace on that emulator, NOT the seeded
/// `why-not-cafe-menu-dev` one `firebase/dev-seed/seed.js` actually
/// writes to (confirmed by a 404 on that project id at :8081 while
/// `why-not-cafe-menu-dev` returns real seeded docs) — so emulator mode
/// needs its own [FirebaseOptions] with the matching project id, same
/// as billing_cafe's own `firebase_options_menu.dart` emulator branch.
const _emulatorOptions = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:000000000000:web:0000000000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'why-not-cafe-menu-dev',
  authDomain: 'why-not-cafe-menu-dev.firebaseapp.com',
);

void main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: _useLocalEmulator ? _emulatorOptions : DefaultFirebaseOptions.currentPlatform,
  );
  if (_useLocalEmulator) {
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8081);
    // A DEDICATED Auth emulator on :9098 for `why-not-cafe-menu-dev`
    // (`firebase/dev-seed/menu-emulator/firebase.json`), NOT billing_cafe's
    // shared :9099 instance — that one is started with `--project
    // demo-why-not-cafe` + `singleProjectMode: true`, which silently
    // forces EVERY sign-in onto the POS project regardless of which
    // project id the client sends (confirmed: a sign-in requesting
    // `why-not-cafe-menu-dev` came back with an ID token whose `aud`
    // was `demo-why-not-cafe` instead) — token/project would mismatch
    // Firestore's own `why-not-cafe-menu-dev` instance and `request.auth`
    // would never resolve. Without this call at all, /admin's
    // Google-popup sign-in (`AuthService.signInWithGoogle`) hits the
    // REAL identitytoolkit API with the fake `demo-api-key` above and
    // is correctly rejected — the original "Sign in failed" symptom.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9098);
  }
  // Fire-and-forget: only /checkout's REST calls need this token (see
  // PosAppCheckService.getToken()'s own null-safe fallback), so it must
  // never delay first paint for the menu-browsing majority of visitors.
  // Never fatal — see PosAppCheckService.activate()'s own doc.
  unawaited(PosAppCheckService.activate());
  runApp(const ProviderScope(child: CafeApp()));
}

class CafeApp extends ConsumerWidget {
  const CafeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Cafe Countryside Menu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      routerConfig: appRouter,
    );
  }
}
