// File generated for Kushk Firebase project (kushk-eb02a).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return web;
      case TargetPlatform.windows:
        return web;
      case TargetPlatform.linux:
        return web;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAC4fc0e0PLPJAta84BKjOhBxb89vcJzF4',
    appId: '1:1057658867946:web:ad77c05d60e876198e4793',
    messagingSenderId: '1057658867946',
    projectId: 'kushk-eb02a',
    authDomain: 'kushk-eb02a.firebaseapp.com',
    storageBucket: 'kushk-eb02a.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCqNwOsLeegXwV1JWqP3MQNJcIAEt0VsNA',
    appId: '1:1057658867946:android:bced052e78ab446b8e4793',
    messagingSenderId: '1057658867946',
    projectId: 'kushk-eb02a',
    storageBucket: 'kushk-eb02a.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB437KMkoDCYVwtkWQ5AP3l379TkAwjs2U',
    appId: '1:1057658867946:ios:160838dd81acb0cd8e4793',
    messagingSenderId: '1057658867946',
    projectId: 'kushk-eb02a',
    storageBucket: 'kushk-eb02a.firebasestorage.app',
    iosBundleId: 'dnz.dnzteam.Kushk',
  );
}
