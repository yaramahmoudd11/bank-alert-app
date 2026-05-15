import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'splash_screen.dart';
import 'firebase_options.dart';
import 'notification_service.dart';
Future<void> initFirebase() async {
  if (Firebase.apps.isNotEmpty) return;

  try {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Firebase.initializeApp();
    } else {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      debugPrint('Firebase already initialized');
    } else {
      rethrow;
    }
  }
}
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await initFirebase();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await initFirebase();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await Supabase.initialize(
      url: 'https://dtrmjuyfclfelfrqxezh.supabase.co',
      anonKey: 'sb_publishable_L3zpCeXGj_SiXKqEKFuvmQ_qHt7GM7C',
    );

    await NotificationService.initialize();

    runApp(const MyApp());
  } catch (e) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Initialization failed: $e',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bank Alerts',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        scaffoldBackgroundColor: const Color(0xfff7f7fb),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}