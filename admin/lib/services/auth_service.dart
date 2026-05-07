import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;

class AdminAuthService {
  AdminAuthService._();
  static final instance = AdminAuthService._();

  final _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return _message(e.code);
    }
  }

  Future<void> signOut() => _auth.signOut();

  String _message(String code) => switch (code) {
        'user-not-found' => 'অ্যাকাউন্ট পাওয়া যায়নি',
        'wrong-password' => 'পাসওয়ার্ড ভুল',
        'invalid-credential' => 'ইমেইল বা পাসওয়ার্ড ভুল',
        'too-many-requests' => 'বারবার ভুল চেষ্টা — একটু পরে চেষ্টা করুন',
        _ => 'লগিন ব্যর্থ ($code)',
      };
}
