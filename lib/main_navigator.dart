import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/report_screen.dart';

class MainNavigator extends StatefulWidget {
  final int userStage;
  final String nickname;
  final String gender;
  final String? imagePath;

  const MainNavigator({
    super.key,
    required this.userStage,
    required this.nickname,
    required this.gender,
    this.imagePath,
  });

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    // ✅ กำหนดให้เหลือเพียง 2 หน้าหลัก
    final List<Widget> _screens = [
      HomeScreen(
        userStage: widget.userStage,
        nickname: widget.nickname,
        gender: widget.gender,
        imagePath: widget.imagePath,
      ),
      ReportScreen(
        userStage: widget.userStage,
        nickname: widget.nickname,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -2))
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          selectedItemColor: const Color(0xFF00D1B2),
          unselectedItemColor: Colors.grey.shade400,
          onTap: (index) => setState(() => _selectedIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedFontSize: 14,
          unselectedFontSize: 14,
          iconSize: 28, // ปรับไอคอนให้ใหญ่ขึ้นเล็กน้อย
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              activeIcon: Icon(Icons.home_rounded, size: 32),
              label: 'หน้าหลัก',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              activeIcon: Icon(Icons.bar_chart_rounded, size: 32),
              label: 'รายงาน',
            ),
          ],
        ),
      ),
    );
  }
}