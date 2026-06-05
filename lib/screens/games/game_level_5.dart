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

class GameLevel5 extends StatefulWidget {
  final int userStage;
  const GameLevel5({super.key, required this.userStage});

  @override
  State<GameLevel5> createState() => _GameLevel5State();
}

class _GameLevel5State extends State<GameLevel5> {
  CameraController? _cameraController;
  final PoseDetector _poseDetector = PoseDetector(options: PoseDetectorOptions());
  bool _isProcessing = false;
  
  Pose? _currentPose;
  Size? _imageSize; 
  Size _canvasSize = Size.zero; 

  GameState _gameState = GameState.setup;
  int _stepsCount = 0;
  final int _targetSteps = 20; 
  int _selectedMinutes = 1; 
  int _timeRemainingSeconds = 0; 
  Timer? _countdownTimer;

  // ✅ ระบบ Auto Countdown และระยะ (0.22 เพื่อให้เห็นเข่า)
  bool _isDistanceOk = false;
  String _distanceHint = "กรุณามายืนหน้ากล้อง";
  Timer? _setupCountdownTimer;
  int _setupCounter = 3;
  bool _isStartingCountdown = false;

  // Logic สำหรับตรวจจับการย่ำ (Hysteresis)
  bool _isLeftKneeUp = false;
  bool _isRightKneeUp = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
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

  void _startGame() {
    _stopSetupCountdown();
    setState(() {
      _stepsCount = 0;
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
    LocalDB().insertScore(5, 100, 0.0, widget.userStage);
    DatabaseService().updateUnlockedLevel(6);
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
        final lHip = pose.landmarks[PoseLandmarkType.leftHip];
        final rHip = pose.landmarks[PoseLandmarkType.rightHip];
        final lKnee = pose.landmarks[PoseLandmarkType.leftKnee];
        final rKnee = pose.landmarks[PoseLandmarkType.rightKnee];

        // ✅ วัดระยะ (0.22 สำหรับ Level 5 เพื่อให้เห็นขา)
        if (lHip != null && rHip != null) {
          double sWidth = (lHip.x - rHip.x).abs() / image.width;
          if (mounted) {
            setState(() {
              _isDistanceOk = sWidth < 0.22; 
              _distanceHint = _isDistanceOk ? "ระยะห่างพร้อมแล้ว ✅" : "กรุณาถอยห่างจนเห็นช่วงขา";
              if (!_isStartingCountdown && _gameState == GameState.setup && _isDistanceOk) {
                _startSetupCountdown();
              }
            });
          }
        }

        if (mounted) setState(() { _currentPose = pose; });

        // 🚶‍♂️ Logic การย่ำเท้า (ปรับปรุงใหม่: Dynamic Threshold)
        if (_gameState == GameState.playing && lHip != null && rHip != null && lKnee != null && rKnee != null) {
          // คำนวณความสูงสะโพกเฉลี่ย (Baseline)
          double hipY = (lHip.y + rHip.y) / 2;
          // คำนวณระยะต้นขาเพื่อหา Threshold ที่เหมาะกับตัวผู้เล่น
          double thighLength = (lHip.y - lKnee.y).abs();
          double liftThreshold = thighLength * 0.3; // ต้องยกเข่าขึ้น 30% ของความยาวขา

          // ตรวจจับเข่าซ้ายยก
          if (lKnee.y < (hipY - liftThreshold)) {
            if (!_isLeftKneeUp) {
              setState(() { _stepsCount++; _isLeftKneeUp = true; });
            }
          } else if (lKnee.y > (hipY - (liftThreshold * 0.5))) {
            _isLeftKneeUp = false; // ต้องวางขาลงมาเกินครึ่งถึงจะเริ่มนับก้าวใหม่ได้
          }

          // ตรวจจับเข่าขวายก
          if (rKnee.y < (hipY - liftThreshold)) {
            if (!_isRightKneeUp) {
              setState(() { _stepsCount++; _isRightKneeUp = true; });
            }
          } else if (rKnee.y > (hipY - (liftThreshold * 0.5))) {
            _isRightKneeUp = false;
          }

          if (_stepsCount >= _targetSteps) _endGame();
        }
      }
    } finally { _isProcessing = false; }
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

            if (_gameState == GameState.playing)
              Positioned(
                top: 20, left: 20,
                child: Row(
                  children: [
                    _buildStatCard('ก้าว: $_stepsCount/$_targetSteps', const Color(0xFF00D1B2)),
                    const SizedBox(width: 10),
                    _buildStatCard(_formattedTime, Colors.redAccent),
                  ],
                ),
              ),

            if (_gameState == GameState.playing)
              Positioned(
                bottom: 30, left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.8), borderRadius: BorderRadius.circular(20)),
                    child: const Text("⚠️ กรุณายืนจับเก้าอี้เพื่อความปลอดภัย", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),

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

  Widget _buildSetupScreen() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20), border: Border.all(color: _isDistanceOk ? const Color(0xFF00D1B2) : Colors.red, width: 3)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Level 5: ย่ำเท้าพาเพลิน 🚶‍♂️", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF00D1B2))),
            const SizedBox(height: 10),
            if (_isStartingCountdown && _isDistanceOk)
               Text("$_setupCounter", style: const TextStyle(fontSize: 100, fontWeight: FontWeight.bold, color: Color(0xFFFFB800)))
            else
              Icon(_isDistanceOk ? Icons.check_circle : Icons.accessibility_new, size: 60, color: _isDistanceOk ? const Color(0xFF00D1B2) : Colors.orange),
            const SizedBox(height: 10),
            Text(_distanceHint, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: _isDistanceOk ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            const Text("ตั้งเวลาเล่น:", style: TextStyle(fontSize: 16)),
            DropdownButton<int>(
              value: _selectedMinutes,
              items: [1, 3, 5].map((int val) => DropdownMenuItem(value: val, child: Text("$val นาที"))).toList(),
              onChanged: (val) => setState(() => _selectedMinutes = val!),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _isDistanceOk ? const Color(0xFFFFB800) : Colors.grey, shape: const StadiumBorder()),
              onPressed: _isDistanceOk ? _startGame : null, 
              child: const Padding(padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12), child: Text("เริ่มเล่น!", style: TextStyle(fontSize: 22, color: Colors.white))),
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
            const Text("สำเร็จ! 🏆", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
            Text("ย่ำไปได้ $_stepsCount ก้าว", style: const TextStyle(fontSize: 28, color: Color(0xFF00D1B2))),
            const SizedBox(height: 30),
            ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("กลับเมนูหลัก")),
          ],
        ),
      ),
    );
  }
}

// --- Painters ---

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
      final paintLine = Paint()..color = const Color(0xFF00D1B2)..strokeWidth = 3.0..style = PaintingStyle.stroke;
      final paintThickLine = Paint()..color = const Color(0xFF00D1B2)..strokeWidth = 8.0..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
      final paintPoint = Paint()..color = const Color(0xFFFFB800)..style = PaintingStyle.fill;
      
      final scaleX = size.width / imageSize!.width;
      final scaleY = size.height / imageSize!.height;
      Offset mapPoint(PoseLandmark lm) => Offset(size.width - (lm.x * scaleX), lm.y * scaleY);

      void drawNormalLine(PoseLandmarkType t1, PoseLandmarkType t2) {
        final l1 = pose!.landmarks[t1]; final l2 = pose!.landmarks[t2];
        if (l1 != null && l2 != null) canvas.drawLine(mapPoint(l1), mapPoint(l2), paintLine);
      }

      void drawThickLine(PoseLandmarkType t1, PoseLandmarkType t2) {
        final l1 = pose!.landmarks[t1]; final l2 = pose!.landmarks[t2];
        if (l1 != null && l2 != null) canvas.drawLine(mapPoint(l1), mapPoint(l2), paintThickLine);
      }

      // วาดโครงสร้างร่างกายปกติ
      drawNormalLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
      drawNormalLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
      drawNormalLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
      drawNormalLine(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);

      // ✅ เน้นช่วงขาให้หนาขึ้นเพื่อให้ผู้เล่นเห็นเป้าหมายการย่ำเท้าชัดๆ
      drawThickLine(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
      drawThickLine(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
      drawThickLine(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);
      drawThickLine(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);

      for (var lm in pose!.landmarks.values) { 
        if (lm.likelihood > 0.5) canvas.drawCircle(mapPoint(lm), 5, paintPoint); 
      }
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}