import 'package:flutter/material.dart';
import 'screening_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 140, height: 140,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F7FA),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00D1B2), width: 4),
                  ),
                  child: const Icon(Icons.health_and_safety, size: 80, color: Color(0xFF00D1B2)),
                ),
                const SizedBox(height: 40),
                const Text("Parkinson Hero", style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF00D1B2))),
                const Text("ระบบฟื้นฟูอัจฉริยะเพื่อคุณ", style: TextStyle(fontSize: 18, color: Colors.grey)),
                const SizedBox(height: 80),

                SizedBox(
                  width: double.infinity, height: 60,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D1B2),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 3,
                    ),
                    child: const Text("เริ่มต้นใช้งาน", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const ScreeningScreen()),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}