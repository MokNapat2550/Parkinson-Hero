import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseService {
  // สร้าง Singleton เพื่อให้เรียกใช้งานได้จากทุกหน้า
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  final _unlockedLevelController = StreamController<int>.broadcast();
  int _currentUnlockedLevel = 1;

  Stream<int> get unlockedLevelStream => _unlockedLevelController.stream;
  int get currentUnlockedLevel => _currentUnlockedLevel;

  // ✅ 1. ฟังก์ชันโหลดค่าด่านที่จำไว้ในเครื่อง (เรียกใช้ตอนเปิดแอป)
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    // ดึงค่า 'unlocked_level' มา ถ้ายังไม่มี (เล่นครั้งแรก) ให้ใช้ค่าเริ่มต้นเป็นด่าน 1
    _currentUnlockedLevel = prefs.getInt('unlocked_level') ?? 1;
    _unlockedLevelController.add(_currentUnlockedLevel);
  }

  // ✅ 2. ฟังก์ชันอัปเดตด่านและบันทึกลงเครื่องถาวร (เรียกตอนเล่นชนะ)
  Future<void> updateUnlockedLevel(int newLevel) async {
    // บันทึกเฉพาะเมื่อด่านใหม่สูงกว่าด่านที่เคยปลดล็อกไว้
    if (newLevel > _currentUnlockedLevel) {
      _currentUnlockedLevel = newLevel;
      _unlockedLevelController.add(_currentUnlockedLevel);
      
      // 🔒 บันทึกค่าลงเครื่อง ปิดแอปไปกี่รอบก็ไม่หาย
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('unlocked_level', _currentUnlockedLevel);
    }
  }
}