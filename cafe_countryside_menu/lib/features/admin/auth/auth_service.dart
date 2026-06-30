import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth;
  const AuthService(this._auth);

  // Flutter Web: opens the Google OAuth popup — no google_sign_in package needed.
  Future<UserCredential> signInWithGoogle() =>
      _auth.signInWithPopup(GoogleAuthProvider());

  Future<void> signOut() => _auth.signOut();
}
