import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../database_service.dart';
import '../../local_db.dart';

enum GameState { setup, playing, gameOver }

class GameLevel4 extends StatefulWidget {
  final int userStage;
  const GameLevel4({super.key, required this.userStage});

  @override
  State<GameLevel4> createState() => _GameLevel4State();
}

class _GameLevel4State extends State<GameLevel4> {
  CameraController? _cameraController;
  final PoseDetector _poseDetector = PoseDetector(options: PoseDetectorOptions());
  bool _isProcessing = false;
  
  Pose? _currentPose;
  Size? _imageSize; 
  Size _canvasSize = Size.zero; 

  GameState _gameState = GameState.setup;
  int _score = 0;
  int _questionIndex = 0;
  String _feedback = "";
  int _selectedMinutes = 1; 
  int _timeRemainingSeconds = 0; 

  // ✅ ระบบ Auto Countdown และระยะ 2 เมตร (0.25)
  bool _isDistanceOk = false;
  String _distanceHint = "กรุณามายืนหน้ากล้อง";
  Timer? _setupCountdownTimer;
  int _setupCounter = 3;
  bool _isStartingCountdown = false;
  
  Timer? _countdownTimer;

  final List<Map<String, dynamic>> _questions = [
    {'q': '5 + 3 = ?', 'left': '8', 'right': '10', 'ans': 1},
    {'q': '10 - 4 = ?', 'left': '5', 'right': '6', 'ans': 2},
    {'q': '2 x 9 = ?', 'left': '18', 'right': '16', 'ans': 1},
    {'q': 'ใบไม้ส่วนใหญ่สีอะไร', 'left': 'เหลือง', 'right': 'เขียว', 'ans': 2},
    {'q': '15 ÷ 3 = ?', 'left': '5', 'right': '3', 'ans': 1},
    {'q': '7 x 6 = ?', 'left': '42', 'right': '48', 'ans': 1},
    {'q': 'เมืองหลวงของไทย', 'left': 'กรุงเทพฯ', 'right': 'เชียงใหม่', 'ans': 1},
    {'q': '20 + 35 = ?', 'left': '45', 'right': '55', 'ans': 2},
    {'q': 'สัตว์ที่บินได้', 'left': 'สุนัข', 'right': 'นก', 'ans': 2},
    {'q': '100 - 25 = ?', 'left': '75', 'right': '85', 'ans': 1},
  ];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  void _startSetupCountdown() {
    if (_isStartingCountdown) return;
    _isStartingCountdown = true;
    _setupCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDistanceOk) {
        setState(() {
          if (_setupCounter > 1) {
            _setupCounter--;
          } else {
            _setupCountdownTimer?.cancel();
            _startGame();
          }
        });
      } else {
        _stopSetupCountdown();
      }
    });
  }

  void _stopSetupCountdown() {
    _setupCountdownTimer?.cancel();
    if (mounted) {
      setState(() {
        _isStartingCountdown = false;
        _setupCounter = 3;
      });
    }
  }

  Future<void> _initializeCamera() async {
    await Permission.camera.request();
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final frontCamera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    await _cameraController?.initialize();
    if (!mounted) return;
    setState(() {});
    _cameraController?.startImageStream((image) {
      if (!_isProcessing) _processImage(image);
    });
  }

  void _startGame() {
    _stopSetupCountdown();
    setState(() {
      _score = 0;
      _questionIndex = 0;
      _timeRemainingSeconds = _selectedMinutes * 60;
      _gameState = GameState.playing;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemainingSeconds > 0) {
        setState(() { _timeRemainingSeconds--; });
      } else {
        _endGame();
      }
    });
  }

  void _endGame() {
    _countdownTimer?.cancel();
    setState(() { _gameState = GameState.gameOver; });
    LocalDB().insertScore(4, _score, 0.0, widget.userStage);
    DatabaseService().updateUnlockedLevel(5);
  }

  Future<void> _processImage(CameraImage image) async {
    _isProcessing = true;
    try {
      final inputImage = _prepareInputImage(image);
      final camera = _cameraController!.description;
      final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
      
      bool isPortrait = imageRotation == InputImageRotation.rotation90deg || imageRotation == InputImageRotation.rotation270deg;
      Size absoluteImageSize = isPortrait 
          ? Size(image.height.toDouble(), image.width.toDouble()) 
          : Size(image.width.toDouble(), image.height.toDouble());

      if (mounted) setState(() { _imageSize = absoluteImageSize; });

      final poses = await _poseDetector.processImage(inputImage);
      
      if (poses.isNotEmpty) {
        final pose = poses.first;
        final lS = pose.landmarks[PoseLandmarkType.leftShoulder];
        final rS = pose.landmarks[PoseLandmarkType.rightShoulder];

        if (lS != null && rS != null) {
          // ✅ วัดระยะ 2 เมตร (0.25)
          double sWidth = (lS.x - rS.x).abs() / image.width;
          if (mounted) {
            setState(() {
              _isDistanceOk = sWidth < 0.25; 
              _distanceHint = _isDistanceOk ? "ระยะห่างเหมาะสมแล้ว ✅" : "กรุณาถอยห่างจากกล้องอีกนิด";
              if (!_isStartingCountdown && _gameState == GameState.setup && _isDistanceOk) {
                _startSetupCountdown();
              }
            });
          }
        }

        if (mounted) setState(() { _currentPose = pose; });

        // 🎮 [Level 4 Feature] ตรวจจับคำตอบ
        if (_gameState == GameState.playing && _feedback.isEmpty && _questionIndex < _questions.length) {
          final lW = pose.landmarks[PoseLandmarkType.leftWrist];
          final rW = pose.landmarks[PoseLandmarkType.rightWrist];
          if (lS != null && rS != null) {
            if (lW != null && lW.likelihood > 0.7 && lW.y < lS.y - 60) {
              _checkAnswer(1);
            } else if (rW != null && rW.likelihood > 0.7 && rW.y < rS.y - 60) {
              _checkAnswer(2);
            }
          }
        }
      }
    } finally { _isProcessing = false; }
  }

  void _checkAnswer(int userAns) async {
    int correctAns = _questions[_questionIndex]['ans'];
    setState(() {
      if (userAns == correctAns) {
        _score += 1;
        _feedback = "ถูกต้อง! 🎉";
      } else {
        _feedback = "ผิดครับ ❌";
      }
    });

    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() {
        _questionIndex++;
        _feedback = "";
        if (_questionIndex >= _questions.length) _endGame();
      });
    }
  }

  InputImage _prepareInputImage(CameraImage image) {
    final bytes = WriteBuffer();
    for (var plane in image.planes) bytes.putUint8List(plane.bytes);
    final camera = _cameraController!.description;
    return InputImage.fromBytes(
      bytes: bytes.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg,
        format: Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _setupCountdownTimer?.cancel();
    _countdownTimer?.cancel();
    _cameraController?.dispose();
    _poseDetector.close();
    super.dispose();
  }

  String get _formattedTime {
    int m = _timeRemainingSeconds ~/ 60;
    int s = _timeRemainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: 1 / _cameraController!.value.aspectRatio,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_canvasSize != constraints.biggest) setState(() { _canvasSize = constraints.biggest; });
                    });
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_cameraController!),
                        if (_gameState == GameState.setup) CustomPaint(painter: DistanceGuidePainter(isOk: _isDistanceOk)),
                        CustomPaint(painter: GameOverlayPainter(pose: _currentPose, imageSize: _imageSize)),
                      ],
                    );
                  },
                ),
              ),
            ),

            Positioned(top: 20, right: 20, child: IconButton(icon: const Icon(Icons.cancel, color: Colors.white70, size: 40), onPressed: () => Navigator.pop(context))),

            // ✅ Score & Time ตำแหน่งเดียวกับ Level 2
            if (_gameState == GameState.playing)
              Positioned(
                top: 20, left: 20,
                child: Row(
                  children: [
                    _buildStatCard('Score: $_score', const Color(0xFF00D1B2)),
                    const SizedBox(width: 10),
                    _buildStatCard(_formattedTime, Colors.redAccent),
                  ],
                ),
              ),

            // ✅ UI คำถาม (ฟีเจอร์ L4)
            if (_gameState == GameState.playing) _buildQuestionUI(),

            if (_gameState == GameState.setup) _buildSetupScreen(),
            if (_gameState == GameState.gameOver) _buildGameOverScreen(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(30)),
      child: Text(text, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildQuestionUI() {
    var q = _questions[_questionIndex < _questions.length ? _questionIndex : 0];
    return Column(
      children: [
        const SizedBox(height: 100),
        Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(20)),
          child: Text(q['q'], style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        ),
        const Spacer(),
        if (_feedback.isNotEmpty)
          _buildStatCard(_feedback, _feedback.contains("ถูก") ? Colors.green : Colors.red),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildChoiceItem("ยกมือซ้าย", q['left'], Colors.cyan),
              _buildChoiceItem("ยกมือขวา", q['right'], Colors.orange),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChoiceItem(String side, String val, Color color) {
    return Column(
      children: [
        Text(side, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Container(
          width: 140,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: color.withOpacity(0.9), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white, width: 2)),
          child: Center(child: Text(val, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white))),
        ),
      ],
    );
  }

  Widget _buildSetupScreen() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20), border: Border.all(color: _isDistanceOk ? const Color(0xFF00D1B2) : Colors.red, width: 3)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Level 4: สมองสั่งการ 🧠", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF00D1B2))),
            const SizedBox(height: 10),
            if (_isStartingCountdown && _isDistanceOk)
               Text("$_setupCounter", style: const TextStyle(fontSize: 100, fontWeight: FontWeight.bold, color: Color(0xFFFFB800)))
            else
              Icon(_isDistanceOk ? Icons.check_circle : Icons.warning_rounded, size: 60, color: _isDistanceOk ? const Color(0xFF00D1B2) : Colors.orange),
            const SizedBox(height: 10),
            Text(_distanceHint, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: _isDistanceOk ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            DropdownButton<int>(
              value: _selectedMinutes,
              items: [1, 3, 5].map((int val) => DropdownMenuItem(value: val, child: Text("$val นาที"))).toList(),
              onChanged: (val) => setState(() => _selectedMinutes = val!),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _isDistanceOk ? const Color(0xFFFFB800) : Colors.grey, shape: const StadiumBorder()),
              onPressed: _isDistanceOk ? _startGame : null, 
              child: const Padding(padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12), child: Text("เริ่มเกม!", style: TextStyle(fontSize: 22, color: Colors.white))),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildGameOverScreen() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("จบเกม 🎉", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
            Text("$_score คะแนน", style: const TextStyle(fontSize: 40, color: Color(0xFF00D1B2))),
            const SizedBox(height: 30),
            ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("กลับเมนูหลัก")),
          ],
        ),
      ),
    );
  }
}

class DistanceGuidePainter extends CustomPainter {
  final bool isOk;
  DistanceGuidePainter({required this.isOk});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = isOk ? Colors.green.withOpacity(0.5) : Colors.red.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 4;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.1, size.height * 0.1, size.width * 0.8, size.height * 0.8), paint);
  }
  @override
  bool shouldRepaint(CustomPainter old) => true;
}

class GameOverlayPainter extends CustomPainter {
  final Pose? pose;
  final Size? imageSize;
  GameOverlayPainter({this.pose, this.imageSize});
  @override
  void paint(Canvas canvas, Size size) {
    if (pose != null && imageSize != null) {
      final paintLine = Paint()..color = const Color(0xFF00D1B2).withOpacity(0.8)..strokeWidth = 4.0..style = PaintingStyle.stroke;
      final paintPoint = Paint()..color = const Color(0xFFFFB800)..style = PaintingStyle.fill;
      final scaleX = size.width / imageSize!.width;
      final scaleY = size.height / imageSize!.height;
      Offset mapPoint(PoseLandmark lm) => Offset(size.width - (lm.x * scaleX), lm.y * scaleY);

      void drawLine(PoseLandmarkType t1, PoseLandmarkType t2) {
        final l1 = pose!.landmarks[t1]; final l2 = pose!.landmarks[t2];
        if (l1 != null && l2 != null) canvas.drawLine(mapPoint(l1), mapPoint(l2), paintLine);
      }
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
      drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightWrist);
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftWrist);
      for (var lm in pose!.landmarks.values) { if (lm.likelihood > 0.5) canvas.drawCircle(mapPoint(lm), 5, paintPoint); }
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}