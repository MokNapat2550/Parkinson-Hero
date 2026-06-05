import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_service.dart';
import 'screening_screen.dart';
import 'games/game_level_1.dart';
import 'games/game_level_2.dart';
import 'games/game_level_3.dart';
import 'games/game_level_4.dart';
import 'games/game_level_5.dart';

class HomeScreen extends StatelessWidget {
  final int userStage; 
  final String nickname;
  final String gender; 
  final String? imagePath; 

  const HomeScreen({
    super.key, 
    required this.userStage, 
    required this.nickname,
    required this.gender,
    this.imagePath,
  });

  // ✅ ฟังก์ชันแปลงเลข Stage เป็นข้อความที่คนเข้าใจง่าย
  String _getStageText(int stage) {
    if (stage == 1) return "1-2";
    if (stage == 2) return "3";
    if (stage == 3) return "4-5";
    return stage.toString();
  }

  // ✅ ฟังก์ชันแจ้งเตือนก่อนออกจากระบบ
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('ออกจากระบบ', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('คุณแน่ใจหรือไม่ว่าต้องการออกจากระบบ? ข้อมูลโปรไฟล์จะถูกล้างและกลับไปหน้าเริ่มต้นครับ', style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear(); 
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const ScreeningScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('ออกจากระบบ', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // การ์ดเกมแบบใหม่
  // ==========================================
  Widget _buildGameCard(BuildContext context, String title, String desc, IconData icon, Color color, bool isWarning, Widget targetScreen, bool isLocked) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))
        ],
        border: isWarning ? Border.all(color: Colors.orange, width: 2) : (isLocked ? Border.all(color: Colors.grey.shade200) : null),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isLocked ? Colors.grey.shade100 : color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(isLocked ? Icons.lock_rounded : icon, size: 35, color: isLocked ? Colors.grey.shade400 : color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isLocked ? Colors.grey.shade400 : Colors.black87)),
                    const SizedBox(height: 4),
                    Text(desc, style: TextStyle(fontSize: 14, color: isLocked ? Colors.grey.shade400 : (isWarning ? Colors.orange : Colors.grey.shade600))),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isLocked ? Colors.grey.shade300 : (isWarning ? Colors.orange : const Color(0xFF00D1B2)), 
                foregroundColor: isLocked ? Colors.grey.shade500 : Colors.white,
                elevation: isLocked ? 0 : 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))
              ),
              onPressed: isLocked ? null : () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => targetScreen));
              },
              child: Text(
                isLocked ? 'ด่านนี้ยังไม่ปลดล็อก' : (isWarning ? 'เล่นโดยมีผู้ดูแล' : 'เริ่มเกม'), 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
              ),
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF00D1B2), 
      body: SafeArea(
        bottom: false, 
        child: StreamBuilder<int>(
          stream: DatabaseService().unlockedLevelStream,
          initialData: DatabaseService().currentUnlockedLevel,
          builder: (context, snapshot) {
            int unlockedLevel = snapshot.data ?? 1;

            int totalLevels = (userStage == 3) ? 1 : 5; 
            int completedLevels = (unlockedLevel - 1).clamp(0, totalLevels);
            double progress = completedLevels / totalLevels;
            int progressPercent = (progress * 100).toInt();

            return Column(
              children: [
                // ==========================================
                // Header (ปรับปรุงการแสดงผลตาม Stage)
                // ==========================================
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('สวัสดีคุณ $nickname', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87)),
                                const SizedBox(height: 5),
                                // ✅ แสดงข้อความ "ระดับ 1-2", "ระดับ 3" ตามที่คุณต้องการ
                                Text(
                                  'ระดับการฝึกวันนี้: ระดับ ${_getStageText(userStage)}', 
                                  style: TextStyle(fontSize: 16, color: Colors.black87.withOpacity(0.7), fontWeight: FontWeight.w500)
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => _showLogoutDialog(context),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.white, 
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]
                              ),
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: gender == 'male' ? const Color(0xFFB3E5FC) : const Color(0xFFF8BBD0),
                                    backgroundImage: imagePath != null ? FileImage(File(imagePath!)) : null,
                                    child: imagePath == null 
                                        ? Icon(gender == 'male' ? Icons.face : Icons.face_3, size: 38, color: Colors.black54)
                                        : null,
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                    child: const Icon(Icons.logout_rounded, size: 12, color: Colors.redAccent),
                                  )
                                ],
                              ),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 25),
                      // หลอดความคืบหน้า
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.white.withOpacity(0.4),
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD166)), 
                                minHeight: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Text('$progressPercent%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                        ],
                      )
                    ],
                  ),
                ),

                // ==========================================
                // ส่วนของรายการเกม (พื้นหลังขาวขอบมน)
                // ==========================================
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF5F7F9), 
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(24.0),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        const Text('เกมที่เหมาะกับคุณวันนี้', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const Text('(แนะนำโดย AI ตามระดับอาการ)', style: TextStyle(fontSize: 14, color: Colors.grey)),
                        const SizedBox(height: 20),

                        _buildGameCard(context, 'Level 1: Seed Planter', 'ฝึกกล้ามเนื้อหัวไหล่', Icons.eco_rounded, const Color(0xFF00D1B2), false, GameLevel1(userStage: userStage), false),

                        if (userStage <= 2) ...[
                          _buildGameCard(context, 'Level 2: Star Gatherer', 'ฝึกยืดเหยียดแขนและกล้ามเนื้อมัดเล็ก ', Icons.star_rounded, const Color(0xFFFFB800), false, GameLevel2(userStage: userStage), unlockedLevel < 2),
                          _buildGameCard(context, 'Level 3: Seated Slalom', 'ฝึกทรงตัวท่านั่ง ', Icons.downhill_skiing_rounded, const Color(0xFF3B82F6), false, GameLevel3(userStage: userStage), unlockedLevel < 3),
                        ],
                        
                        if (userStage == 1) ...[
                          _buildGameCard(context, 'Level 4: Mind & Motion', 'สมองและร่างกาย ', Icons.psychology_rounded, Colors.purpleAccent, false, GameLevel4(userStage: userStage), unlockedLevel < 4),
                          _buildGameCard(context, 'Level 5: Marching Hero', 'ฝึกจังหวะการเดิน ', Icons.directions_walk_rounded, Colors.redAccent, false, GameLevel5(userStage: userStage), unlockedLevel < 5),
                        ],
                            
                        if (userStage == 2) ...[
                          _buildGameCard(context, 'Level 4: Mind & Motion', 'ฝึกทำสองอย่างพร้อมกัน (ท่านั่ง)', Icons.psychology_rounded, Colors.purpleAccent, false, GameLevel4(userStage: userStage), unlockedLevel < 4),
                          _buildGameCard(context, 'Level 5: Marching (จำกัด)', 'คำเตือน: ระวังการล้ม', Icons.warning_amber_rounded, Colors.orange, true, GameLevel5(userStage: userStage), unlockedLevel < 5),
                        ],
                            
                        if (userStage == 3)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red.shade200)),
                            child: const Column(
                              children: [
                                Icon(Icons.medical_information, color: Colors.red, size: 40),
                                SizedBox(height: 10),
                                Text(
                                  'เพื่อความปลอดภัย ระบบจำกัดเฉพาะเกมที่ฝึกกล้ามเนื้อมัดเล็ก (Level 1)\nกรุณาฝึกภายใต้การดูแลของผู้เชี่ยวชาญ', 
                                  textAlign: TextAlign.center, 
                                  style: TextStyle(color: Colors.red, height: 1.5, fontWeight: FontWeight.w500)
                                ),
                              ],
                            ),
                          )
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
        ),
      ),
    );
  }
}