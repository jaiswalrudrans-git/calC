// File generated for Firebase Spark backend configuration
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for the metric-app Firebase Spark project.
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
      case TargetPlatform.windows:
        return windows;
      default:
        return android;
    }
  }

  // Configuration for Android
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA98shp0IpVg4TtZugzrNoRSLVJFMD9ZBk',
    appId: '1:774689759717:android:9dbebfbcb6bc6b3c75cf0c',
    messagingSenderId: '774689759717',
    projectId: 'metric-app-af543',
    storageBucket: 'metric-app-af543.firebasestorage.app',
  );

  // Configuration for iOS
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA98shp0IpVg4TtZugzrNoRSLVJFMD9ZBk',
    appId: '1:774689759717:ios:metricapp000000',
    messagingSenderId: '774689759717',
    projectId: 'metric-app-af543',
    storageBucket: 'metric-app-af543.firebasestorage.app',
    iosBundleId: 'com.metric.app.metric',
  );

  // Configuration for Windows / Desktop
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyA98shp0IpVg4TtZugzrNoRSLVJFMD9ZBk',
    appId: '1:774689759717:web:metricapp000000',
    messagingSenderId: '774689759717',
    projectId: 'metric-app-af543',
    storageBucket: 'metric-app-af543.firebasestorage.app',
  );

  // Configuration for Web
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA98shp0IpVg4TtZugzrNoRSLVJFMD9ZBk',
    appId: '1:774689759717:web:metricapp000000',
    messagingSenderId: '774689759717',
    projectId: 'metric-app-af543',
    storageBucket: 'metric-app-af543.firebasestorage.app',
  );
}
