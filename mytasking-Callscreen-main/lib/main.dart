import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/voip_call_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
  runApp(const NexaCorpCallApp());
}

class NexaCorpCallApp extends StatelessWidget {
  const NexaCorpCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Addphonebook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050A18),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const VoipCallScreen(),
    );
  }
}
