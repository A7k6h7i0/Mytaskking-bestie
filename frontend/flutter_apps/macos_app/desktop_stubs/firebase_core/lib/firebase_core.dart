library firebase_core;

class FirebaseOptions {
  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String? storageBucket;
  final String? iosBundleId;

  const FirebaseOptions({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    this.storageBucket,
    this.iosBundleId,
  });
}

class FirebaseApp {
  const FirebaseApp();
}

class Firebase {
  static final List<FirebaseApp> apps = <FirebaseApp>[];

  static Future<FirebaseApp> initializeApp({FirebaseOptions? options}) async {
    if (apps.isEmpty) {
      apps.add(const FirebaseApp());
    }
    return apps.first;
  }
}
