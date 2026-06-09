import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../main_navigator.dart';

class ScreeningScreen extends StatefulWidget {
  const ScreeningScreen({super.key});

  @override
  State<ScreeningScreen> createState() => _ScreeningScreenState();
}

class _ScreeningScreenState extends State<ScreeningScreen> {
  final PageController _pageController = PageController(); // ✅ ใช้ควบคุมการเปลี่ยนหน้า
  final ImagePicker _picker = ImagePicker();

  String? _imagePath;
  String? _selectedGender;
  final TextEditingController _nameController = TextEditingController();
  int? _selectedStage;

  // --- ไปหน้าถัดไป ---
  void _nextPage() {
  }

  // --- ย้อนกลับ ---
  void _prevPage() {
    _pageController.previousPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
  }

  // --- เลือกรูป ---
  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() => _imagePath = image.path);
        // เลือกเสร็จ รอ 0.5 วิ แล้วไปหน้าถัดไปอัตโนมัติ
        Future.delayed(const Duration(milliseconds: 500), _nextPage);
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  // --- บันทึกข้อมูลและเข้าแอป ---
  Future<void> _completeOnboarding() async {
    if (_selectedStage == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_gender', _selectedGender ?? 'other');
    await prefs.setString('user_nickname', _nameController.text.trim());
    await prefs.setInt('user_stage', _selectedStage!);
    if (_imagePath != null) await prefs.setString('user_image_path', _imagePath!);

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => MainNavigator(
            userStage: _selectedStage!,
            nickname: _nameController.text.trim(),
            gender: _selectedGender ?? 'other',
            imagePath: _imagePath,
          ),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ✅ แถบปุ่มย้อนกลับ (ซ่อนในหน้าแรกสุด)
            Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 10, top: 10),
              height: 50,
              child: AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  double page = _pageController.hasClients ? (_pageController.page ?? 0) : 0;
                  if (page > 0) {
                    return IconButton(icon: const Icon(Icons.arrow_back_ios_new), onPressed: _prevPage);
                  }
                  return const SizedBox();
                },
              ),
            ),

            // ✅ ส่วนเนื้อหาหลัก
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // ปิดการปัดหน้าจอ ต้องกดปุ่มเท่านั้น
                children: [
                  _stepWelcome(), // Step 1
                  _stepImage(),   // Step 2
                  _stepGender(),  // Step 3
                  _stepName(),    // Step 4
                  _stepStage(),   // Step 5
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================
  // หน้า 1: ยินดีต้อนรับ
  // =====================================
  Widget _stepWelcome() {
    return Padding(
      padding: const EdgeInsets.all(30.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF00D1B2).withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.favorite, size: 80, color: Color(0xFF00D1B2)),
          ),
          const SizedBox(height: 40),
          const Text('ยินดีต้อนรับสู่\nParkinson Hero', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, height: 1.2)),
          const SizedBox(height: 15),
          const Text('แอปพลิเคชันสำหรับฝึกฝนและทำกายภาพบำบัดสำหรับผู้ป่วยโรคพาร์กินสัน', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 50),
          _buildPrimaryButton('เริ่มต้นใช้งาน', _nextPage),
        ],
      ),
    );
  }

  // =====================================
  // หน้า 2: อัปโหลดรูปโปรไฟล์
  // =====================================
  Widget _stepImage() {
    return Padding(
      padding: const EdgeInsets.all(30.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('ขอรูปหล่อๆ สวยๆ หน่อยครับ', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 70,
                  backgroundColor: Colors.grey.shade100,
                  backgroundImage: _imagePath != null ? FileImage(File(_imagePath!)) : null,
                  child: _imagePath == null ? Icon(Icons.person, size: 70, color: Colors.grey.shade400) : null,
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(color: Color(0xFF00D1B2), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5)]),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 24),
                )
              ],
            ),
          ),
          const SizedBox(height: 40),
          TextButton(
            onPressed: _nextPage,
            child: const Text('ข้ามไปก่อน', style: TextStyle(color: Colors.grey, fontSize: 16, decoration: TextDecoration.underline)),
          )
        ],
      ),
    );
  }

  // =====================================
  // หน้า 3: เลือกเพศ
  // =====================================
  Widget _stepGender() {
    return Padding(
      padding: const EdgeInsets.all(30.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('เลือกเพศของคุณ', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildGenderButton('ชาย', 'male', Icons.face, const Color(0xFFB3E5FC)),
              _buildGenderButton('หญิง', 'female', Icons.face_3, const Color(0xFFF8BBD0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGenderButton(String label, String value, IconData icon, Color color) {
    return GestureDetector(
      onTap: () {
        setState(() => _selectedGender = value);
        Future.delayed(const Duration(milliseconds: 300), _nextPage); // กดแล้วไปต่ออัตโนมัติ
      },
      child: Column(
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: _selectedGender == value ? color : Colors.grey.shade100,
              shape: BoxShape.circle,
              border: Border.all(color: _selectedGender == value ? color : Colors.transparent, width: 4),
            ),
            child: Icon(icon, size: 50, color: _selectedGender == value ? Colors.black87 : Colors.grey),
          ),
          const SizedBox(height: 15),
          Text(label, style: TextStyle(fontSize: 18, fontWeight: _selectedGender == value ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  // =====================================
  // หน้า 4: ใส่ชื่อเล่น
  // =====================================
  Widget _stepName() {
    return Padding(
      padding: const EdgeInsets.all(30.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('โปรดกรอกชื่อเล่น', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 30),
          TextField(
            controller: _nameController,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22),
            decoration: InputDecoration(
              hintText: 'พิมพ์ชื่อเล่นที่นี่',
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 30),
          _buildPrimaryButton('ไปต่อเลย!', () {
            if (_nameController.text.trim().isNotEmpty) _nextPage();
          }),
        ],
      ),
    );
  }

  // =====================================
  // หน้า 5: เลือกระดับอาการ (Stage)
  // =====================================
  Widget _stepStage() {
    return Padding(
      padding: const EdgeInsets.all(30.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('คุณ ${_nameController.text} รู้สึกอย่างไรบ้างครับ?', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('เลือกระยะอาการเพื่อปรับเกมให้เหมาะสม', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 30),
          _buildStageItem(1, 'ระดับ 1-2', 'เดินได้ปกติ สั่นนิดหน่อย', const Color(0xFFB5EAD7)),
          _buildStageItem(2, 'ระดับ 3', 'เดินเซ เริ่มทรงตัวผิดปกติ', const Color(0xFFFFD3B6)),
          _buildStageItem(3, 'ระดับ 4-5', 'เคลื่อนไหวลำบาก ต้องมีคนช่วย', const Color(0xFFFF9AA2)),
        ],
      ),
    );
  }

  Widget _buildStageItem(int val, String title, String desc, Color color) {
    return GestureDetector(
      onTap: () {
        setState(() => _selectedStage = val);
        _completeOnboarding(); // หน้าสุดท้าย กดแล้วเข้าแอปเลย
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text(desc),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  // --- ปุ่มกดหลัก ---
  Widget _buildPrimaryButton(String text, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00D1B2),
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      onPressed: onPressed,
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}