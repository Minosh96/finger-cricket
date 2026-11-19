// Firebase configuration for Finger Cricket (Android, Spark plan).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyADQfjOeTfrX1BdIYVuw_OQZQQJR-r_7ks',
    appId: '1:260489670711:android:0161d9252774d364c08fb2',
    messagingSenderId: '260489670711',
    projectId: 'finger-cricket-3abbc',
    databaseURL:
        'https://finger-cricket-3abbc-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'finger-cricket-3abbc.firebasestorage.app',
  );
}
