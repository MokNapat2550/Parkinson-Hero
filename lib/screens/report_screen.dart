import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../local_db.dart';

class ReportScreen extends StatefulWidget {
  final int userStage;
  final String nickname;
  const ReportScreen({super.key, required this.userStage, required this.nickname});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  // 🎨 Color Palette (ธีมสีเขียว-ขาว แบบแอปสุขภาพ)
  final Color primaryTeal = const Color(0xFF00D1B2);
  final Color bgColor = const Color(0xFFF5F7F9);
  final Color darkText = const Color(0xFF1E293B);
  final Color yellowButton = const Color(0xFFFFC107);
  final Color safeGreen = const Color(0xFF10B981);
  final Color alertRed = const Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryTeal, // พื้นหลังหลักสีเขียว
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: LocalDB().getScoresByStage(widget.userStage),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return _buildEmptyState();
            }

            final rawData = snapshot.data!;

            return Column(
              children: [
                // ==========================================
                // 1. Header (สีเขียวด้านบน)
                // ==========================================
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'รายงานความเก่ง\nของคุณ ${widget.nickname}',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, height: 1.2),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                        child: Text("ส่งออก", style: TextStyle(color: darkText, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                ),

                // ==========================================
                // 2. Body (พื้นหลังขาวขอบมน)
                // ==========================================
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
                    ),
                    child: RefreshIndicator(
                      onRefresh: () async => setState(() {}),
                      child: ListView(
                        padding: const EdgeInsets.all(24.0),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          // 2.1 ข้อความสรุปให้กำลังใจ + คำแนะนำ (แทน 4 ช่องแบบเดิม)
                          _buildEncouragementCard(rawData),
                          const SizedBox(height: 20),

                          // 2.2 กราฟเส้นพัฒนาการคะแนน
                          _buildLineChartCard(rawData),
                          const SizedBox(height: 20),

                          // 2.3 การ์ดสถิติแนวตั้ง (แบบในรูป)
                          _buildVerticalStats(rawData),
                          const SizedBox(height: 25),

                          // 2.4 กราฟแมงมุม (5 ด้าน) ทางการแพทย์ยังคงไว้
                          const Text("วิเคราะห์ทักษะ 5 ด้าน", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 15),
                          _buildRadarChartCard(rawData),
                          const SizedBox(height: 30),

                          // 2.5 ปุ่มสีเหลืองด้านล่าง
                          SizedBox(
                            width: double.infinity,
                            height: 65,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: yellowButton,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                elevation: 0,
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text("เยี่ยมมาก", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                                  Text("พรุ่งนี้มาออกกำลังกายกันอีกนะ", style: TextStyle(fontSize: 14, color: Colors.black87)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ==========================================
  // WIDGETS COMPONENTS
  // ==========================================

  // --- 1. การ์ดสรุปผลและให้คำแนะนำแบบภาษาคน ---
  Widget _buildEncouragementCard(List<Map<String, dynamic>> data) {
    // คำนวณหาด่านที่คะแนนน้อยที่สุดเพื่อแนะนำ
    List<double> avgScores = List.filled(5, 0.0);
    List<int> counts = List.filled(5, 0);

    for (var item in data) {
      int lvl = (item['level'] as int) - 1;
      if (lvl >= 0 && lvl < 5) {
        avgScores[lvl] += (item['score'] as num).toDouble();
        counts[lvl]++;
      }
    }

    int weakestLevel = -1;
    double minScore = double.infinity;

    for (int i = 0; i < 5; i++) {
      if (counts[i] > 0) {
        double avg = avgScores[i] / counts[i];
        if (avg < minScore) {
          minScore = avg;
          weakestLevel = i;
        }
      }
    }

    String advice = "คุณเก่งมากครับ พยายามฝึกฝนต่อไปนะครับ ✌️";
    if (weakestLevel == 0) advice = "💡 คำแนะนำ: คุณทำได้ดีมากครับ! แต่ลองฝึกหยิบจับของชิ้นเล็กๆ เพิ่มเติม เพื่อพัฒนากล้ามเนื้อมือนะครับ";
    if (weakestLevel == 1) advice = "💡 คำแนะนำ: วันนี้เก่งมากครับ! ตอนเย็นลองยืดแขนให้สุดเวลาเอื้อมหยิบของ เพื่อลดอาการไหล่ติดนะครับ";
    if (weakestLevel == 2) advice = "💡 คำแนะนำ: ยอดเยี่ยมครับ! ช่วงนี้เวลาทำกิจกรรมให้นั่งพิงเก้าอี้เพื่อความปลอดภัยในการทรงตัวนะครับ";
    if (weakestLevel == 3) advice = "💡 คำแนะนำ: เก่งมากครับคุณย่า! ลองฝึกทำกิจกรรมช้าๆ ทีละอย่าง ไม่ต้องรีบร้อนนะครับ";
    if (weakestLevel == 4) advice = "💡 คำแนะนำ: สุดยอดเลยครับ! เวลาเดินลองให้ลูกหลานหรือคนใกล้ตัวช่วยนับจังหวะ 1-2 ช้าๆ จะช่วยให้ก้าวเดินได้มั่นใจขึ้นครับ";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4), // สีเขียวอ่อนสุดๆ
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: safeGreen.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text("🌟", style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Text("สรุปผลวันนี้", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: safeGreen)),
            ],
          ),
          const SizedBox(height: 10),
          Text(advice, style: TextStyle(fontSize: 15, color: darkText, height: 1.5)),
        ],
      ),
    );
  }

  // --- 2. กราฟเส้นพัฒนาการ (เรียบง่าย) ---
  Widget _buildLineChartCard(List<Map<String, dynamic>> data) {
    var recentData = data.length > 7 ? data.sublist(data.length - 7) : data;
    return Container(
      height: 220,
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("พัฒนาการคะแนน", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: recentData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value['score'] as num).toDouble())).toList(),
                    isCurved: true,
                    color: primaryTeal,
                    barWidth: 4,
                    dotData: FlDotData(show: true, getDotPainter: (a, b, c, d) => FlDotCirclePainter(radius: 4, color: Colors.white, strokeWidth: 2, strokeColor: primaryTeal)),
                    belowBarData: BarAreaData(
                      show: true, 
                      gradient: LinearGradient(colors: [primaryTeal.withOpacity(0.3), primaryTeal.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 3. สถิติแนวตั้ง (ความแม่นยำ, ฝึกต่อเนื่อง) ---
  Widget _buildVerticalStats(List<Map<String, dynamic>> data) {
    double totalScore = data.fold(0.0, (sum, item) => sum + (item['score'] as num).toDouble());
    double avgScore = totalScore / data.length;
    int bestScore = data.map((e) => (e['score'] as num).toInt()).reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        _buildStatRowItem(Icons.emoji_events_rounded, "คะแนนสูงสุด", "$bestScore คะแนน"),
        const SizedBox(height: 12),
        _buildStatRowItem(Icons.track_changes_rounded, "คะแนนเฉลี่ย", "${avgScore.toStringAsFixed(1)} คะแนน"),
        const SizedBox(height: 12),
        _buildStatRowItem(Icons.local_fire_department_rounded, "ความขยัน", "ฝึกไปแล้ว ${data.length} ครั้ง!"),
      ],
    );
  }

  Widget _buildStatRowItem(IconData icon, String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: primaryTeal, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText)),
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- 4. กราฟแมงมุม (สำหรับวิเคราะห์เชิงลึก 5 ด้าน) ---
  Widget _buildRadarChartCard(List<Map<String, dynamic>> data) {
    List<double> avg = List.filled(5, 0.0);
    List<int> counts = List.filled(5, 0);

    for (var item in data) {
      int lvl = (item['level'] as int) - 1;
      if (lvl >= 0 && lvl < 5) {
        avg[lvl] += (item['score'] as num).toDouble();
        counts[lvl]++;
      }
    }
    for (int i = 0; i < 5; i++) avg[i] = counts[i] > 0 ? avg[i] / counts[i] : 10.0;

    return Container(
      height: 280,
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: RadarChart(
        RadarChartData(
          tickCount: 3,
          ticksTextStyle: const TextStyle(color: Colors.transparent),
          titlePositionPercentageOffset: 0.2,
          getTitle: (index, angle) {
            final titles = ['มัดเล็ก', 'ยืดเหยียด', 'ทรงตัว', 'สมอง', 'การเดิน'];
            return RadarChartTitle(text: titles[index], angle: 0);
          },
          dataSets: [
            RadarDataSet(fillColor: primaryTeal.withOpacity(0.3), borderColor: primaryTeal, entryRadius: 3, borderWidth: 2, dataEntries: avg.map((s) => RadarEntry(value: s)).toList()),
          ],
        ),
      ),
    );
  }

  // --- Helper: ดีไซน์ขอบและเงาของการ์ด ---
  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      border: Border.all(color: Colors.grey.shade100),
    );
  }

Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // เปลี่ยนสีไอคอนให้เข้ากับธีมด้วยครับ
          Icon(Icons.monitor_heart_outlined, size: 80, color: const Color.fromARGB(255, 62, 62, 62).withOpacity(0.3)),
          const SizedBox(height: 16),
          // ✅ ลบ const ออกแล้ว และจัดวงเล็บใหม่ให้ถูกต้อง
          Text(
            "ยังไม่มีรายงานผล",
            style: TextStyle(
              color: Colors.white, 
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "เมื่อคุณเริ่มเล่นเกม รายงานจะโผล่ที่นี่",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}