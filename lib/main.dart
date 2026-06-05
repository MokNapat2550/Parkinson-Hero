import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'database_service.dart';
import 'screens/screening_screen.dart'; 
import 'main_navigator.dart'; 
import 'package:google_fonts/google_fonts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await DatabaseService().init();

  final prefs = await SharedPreferences.getInstance();
  final int? savedStage = prefs.getInt('user_stage');
  final String? savedName = prefs.getString('user_nickname');
  final String? savedGender = prefs.getString('user_gender');
  final String? savedImagePath = prefs.getString('user_image_path'); // ✅ ดึงรูป

  runApp(ParkinsonHeroApp(
    savedStage: savedStage,
    savedName: savedName,
    savedGender: savedGender,
    savedImagePath: savedImagePath, // ✅ ส่งต่อ
  ));
}

class ParkinsonHeroApp extends StatelessWidget {
  final int? savedStage;
  final String? savedName;
  final String? savedGender;
  final String? savedImagePath; // ✅ รับค่ารูป

  const ParkinsonHeroApp({
    super.key, 
    this.savedStage, 
    this.savedName, 
    this.savedGender,
    this.savedImagePath,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parkinson Hero',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        primaryColor: const Color(0xFF00D1B2),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00D1B2)),
        textTheme: GoogleFonts.notoSansThaiTextTheme(Theme.of(context).textTheme),
        useMaterial3: true,
      ),
      home: (savedStage != null && savedName != null && savedGender != null) 
          ? MainNavigator(
              userStage: savedStage!,
              nickname: savedName!,
              gender: savedGender!,
              imagePath: savedImagePath, // ✅ ส่งต่อให้ Navigator
            ) 
          : const ScreeningScreen(),
    );
  }
}