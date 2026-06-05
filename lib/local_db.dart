import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDB {
  static Database? _database;

  // เปิดการเชื่อมต่อฐานข้อมูล
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  _initDB() async {
    String path = join(await getDatabasesPath(), 'parkinson_hero.db');
    return await openDatabase(path, version: 1, onCreate: (db, version) async {
      // สร้างตารางเก็บคะแนน
      await db.execute('''
        CREATE TABLE scores (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          level INTEGER,
          user_stage INTEGER,
          score INTEGER,
          reaction_time REAL,
          date TEXT
        )
      ''');
    });
  }

  // 1. ฟังก์ชันบันทึกข้อมูล (ใช้ตอนเล่นเกมจบ)
  Future<void> insertScore(int level, int score, double reactionTime, int userStage) async {
    final db = await database;
    await db.insert('scores', {
      'level': level,
      'user_stage': userStage,
      'score': score,
      'reaction_time': reactionTime,
      'date': DateTime.now().toIso8601String(), // เก็บวันเวลาที่เล่น
    });
    print("บันทึกข้อมูลสำเร็จ: Level $level Score $score");
  }

  // 2. ฟังก์ชันดึงข้อมูลมาวาดกราฟ (ใช้ในหน้า Report)
  Future<List<Map<String, dynamic>>> getScoresByStage(int stage) async {
    final db = await database;
    return await db.query(
      'scores',
      where: 'user_stage = ?',
      whereArgs: [stage],
      orderBy: 'date ASC',
    );
  }
}