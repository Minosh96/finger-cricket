import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../firebase_options.dart';

/// Must match setGlobalOptions({ region }) in functions/src/index.ts.
const String kFunctionsRegion = 'asia-south1';

class OnlineException implements Exception {
  final String message;
  OnlineException(this.message);
  @override
  String toString() => message;
}

/// Everything that talks to Firebase lives here.
class OnlineService {
  OnlineService._();
  static final OnlineService instance = OnlineService._();

  bool firebaseReady = false;
  String? initError;
  int serverOffsetMs = 0;
  StreamSubscription<DatabaseEvent>? _offsetSub;
  StreamSubscription<DatabaseEvent>? _connSub;
  DatabaseReference? _presenceRef;

  Future<void> init() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      firebaseReady = true;
    } catch (e) {
      // Happens until `flutterfire configure` has been run. Offline mode still works.
      firebaseReady = false;
      initError = e.toString();
    }
  }

  String? get uid => firebaseReady ? FirebaseAuth.instance.currentUser?.uid : null;

  /// Server time estimated from RTDB's clock offset – used for every countdown.
  int get serverNow => DateTime.now().millisecondsSinceEpoch + serverOffsetMs;

  Future<String> ensureSignedIn() async {
    if (!firebaseReady) {
      throw OnlineException('Online play is not set up in this build yet. '
          'Use Pass & Play, or follow the README to connect Firebase.');
    }
    final auth = FirebaseAuth.instance;
    var user = auth.currentUser;
    user ??= (await auth.signInAnonymously()).user;
    if (user == null) throw OnlineException('Could not sign in. Check your internet connection.');
    _offsetSub ??= FirebaseDatabase.instance.ref('.info/serverTimeOffset').onValue.listen((e) {
      final v = e.snapshot.value;
      if (v is num) serverOffsetMs = v.toInt();
    });
    return user.uid;
  }

  /// Calls the single `api` Cloud Function.
  Future<Map<String, dynamic>> call(String action, [Map<String, dynamic> data = const {}]) async {
    await ensureSignedIn();
    try {
      final callable = FirebaseFunctions.instanceFor(region: kFunctionsRegion).httpsCallable(
        'api',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
      );
      final res = await callable.call(<String, dynamic>{'action': action, ...data});
      final d = res.data;
      if (d is Map) return d.map((k, v) => MapEntry(k.toString(), v));
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      throw OnlineException(e.message ?? e.code);
    }
  }

  /// Fire-and-forget call (warm-up, tick). Errors are ignored.
  void callQuietly(String action, [Map<String, dynamic> data = const {}]) {
    call(action, data).then((_) {}, onError: (Object _) {});
  }

  Stream<Object?> roomStream(String code) =>
      FirebaseDatabase.instance.ref('rooms/$code').onValue.map((e) => e.snapshot.value);

  /// Secret move: written once, straight to the database. Security rules
  /// reject it after the server deadline, and nobody can read /moves.
  Future<void> submitMove(String code, String roundKey, String uid, int move) {
    return FirebaseDatabase.instance.ref().update(<String, Object?>{
      'moves/$code/$roundKey/$uid': move,
      'rooms/$code/locks/$roundKey/$uid': true,
    });
  }

  /// Keeps players/{uid}/connected up to date, including when the app dies.
  void startPresence(String code, String uid) {
    stopPresence();
    final ref = FirebaseDatabase.instance.ref('rooms/$code/players/$uid/connected');
    _presenceRef = ref;
    _connSub = FirebaseDatabase.instance.ref('.info/connected').onValue.listen((e) async {
      if (e.snapshot.value == true) {
        try {
          await ref.onDisconnect().set(false);
          await ref.set(true);
        } catch (_) {
          // Not a member any more – ignore.
        }
      }
    });
  }

  void stopPresence() {
    _connSub?.cancel();
    _connSub = null;
    final ref = _presenceRef;
    _presenceRef = null;
    if (ref != null) {
      ref.onDisconnect().cancel().then((_) {}, onError: (Object _) {});
    }
  }
}
