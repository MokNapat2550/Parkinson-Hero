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

class FallingCoin {
  Offset position;
  double speed;
  FallingCoin(this.position, this.speed);
}

enum GameState { setup, playing, gameOver }

class GameLevel3 extends StatefulWidget {
  final int userStage;
  const GameLevel3({super.key, required this.userStage});

  @override
  State<GameLevel3> createState() => _GameLevel3State();
}

class _GameLevel3State extends State<GameLevel3> {
  CameraController? _cameraController;
  final PoseDetector _poseDetector = PoseDetector(options: PoseDetectorOptions());
  bool _isProcessing = false;
  
  Pose? _currentPose;
  Size? _imageSize; 
  Size _canvasSize = Size.zero; 

  GameState _gameState = GameState.setup;
  int _score = 0;
  int _selectedMinutes = 1; 
  int _timeRemainingSeconds = 0; 
  
  // ✅ ระบบ Auto Countdown & Distance
  bool _isDistanceOk = false;
  String _distanceHint = "กรุณามายืนหน้ากล้อง";
  Timer? _setupCountdownTimer;
  int _setupCounter = 3;
  bool _isStartingCountdown = false;

  List<FallingCoin> _activeCoins = [];
  Timer? _gameLoop;
  Timer? _countdownTimer;
  
  double _playerXPosition = 0.5; 
  final double _hitRadius = 60.0; // ขยายรัศมีการเก็บเหรียญให้ง่ายขึ้น
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  // ✅ ระบบนับถอยหลังเริ่มเกมอัตโนมัติเมื่อระยะพร้อม
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

    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

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
      _timeRemainingSeconds = _selectedMinutes * 60;
      _activeCoins.clear();
      _gameState = GameState.playing;
      _playerXPosition = 0.5;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemainingSeconds > 0) {
        setState(() { _timeRemainingSeconds--; });
      } else {
        _endGame();
      }
    });

    _gameLoop = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!mounted || _gameState != GameState.playing) return;
      setState(() {
        for (var coin in _activeCoins) {
          coin.position = Offset(coin.position.dx, coin.position.dy + coin.speed);
        }
        _activeCoins.removeWhere((coin) => coin.position.dy > _canvasSize.height);
        if (_random.nextDouble() < 0.03 && _activeCoins.length < 4) _spawnCoin();
        _checkCollision();
      });
    });
  }

  void _endGame() {
    _countdownTimer?.cancel();
    _gameLoop?.cancel();
    setState(() => _gameState = GameState.gameOver);
    LocalDB().insertScore(3, _score, 0.0, widget.userStage);
    DatabaseService().updateUnlockedLevel(4);
  }

  void _spawnCoin() {
    if (_canvasSize == Size.zero) return;
    double startX = 60 + _random.nextDouble() * (_canvasSize.width - 120);
    double speed = 4 + _random.nextDouble() * 3; 
    _activeCoins.add(FallingCoin(Offset(startX, -50), speed));
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
          // ✅ วัดระยะ
          double sWidth = (lS.x - rS.x).abs() / image.width;
          if (mounted) {
            setState(() {
              _isDistanceOk = sWidth < 0.28; 
              _distanceHint = _isDistanceOk ? "ระยะห่างพร้อมแล้ว ✅" : "กรุณาถอยห่างอีกนิด";
              if (!_isStartingCountdown && _gameState == GameState.setup && _isDistanceOk) {
                _startSetupCountdown();
              }
            });
          }

          // ✅ 🎮 Logic การเอี้ยวตัว (High Sensitivity สำหรับผู้สูงอายุ)
          if (_gameState == GameState.playing && _imageSize != null) {
            double midPointX = (lS.x + rS.x) / 2;
            double rawNormalizedX = 1.0 - (midPointX / _imageSize!.width);

            // ปรับความไว: เอี้ยวนิดเดียวตัวละครไปไกล
            double sensitivity = 2.8; 
            double boostedX = ((rawNormalizedX - 0.5) * sensitivity) + 0.5;
            double finalX = boostedX.clamp(0.0, 1.0);

            setState(() {
              // Smoothing 0.5 คือสมดุลระหว่างความไวและความนิ่ง
              _playerXPosition = (_playerXPosition * 0.5) + (finalX * 0.5);
            });
          }
        }
        if (mounted) setState(() { _currentPose = pose; });
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

  void _checkCollision() {
    if (_activeCoins.isEmpty || _canvasSize == Size.zero) return;
    double playerX = _playerXPosition * _canvasSize.width;
    double playerY = _canvasSize.height - 120;
    _activeCoins.removeWhere((coin) {
      double dist = sqrt(pow(playerX - coin.position.dx, 2) + pow(playerY - coin.position.dy, 2));
      if (dist < _hitRadius) {
        _score++;
        return true;
      }
      return false;
    });
  }

  @override
  void dispose() {
    _setupCountdownTimer?.cancel();
    _countdownTimer?.cancel();
    _gameLoop?.cancel();
    _cameraController?.dispose();
    _poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Background
          Image.network('https://images.unsplash.com/photo-1483921020237-2ff51e8e4b22?q=80&w=2070&auto=format&fit=crop', fit: BoxFit.cover),
          Container(color: Colors.black.withOpacity(0.3)),

          // 2. Camera Preview (Overlay Small)
          Positioned(
            top: 100, right: 20, width: 100, height: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(fit: StackFit.expand, children: [
                CameraPreview(_cameraController!),
                CustomPaint(painter: GameOverlayPainter(pose: _currentPose, imageSize: _imageSize)),
              ]),
            ),
          ),

          // 3. Game Layer
          LayoutBuilder(builder: (context, constraints) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_canvasSize != constraints.biggest) setState(() => _canvasSize = constraints.biggest);
            });
            return Stack(
              fit: StackFit.expand,
              children: [
                if (_gameState == GameState.setup) Center(child: CustomPaint(size: constraints.biggest, painter: DistanceGuidePainter(isOk: _isDistanceOk))),
                if (_gameState == GameState.playing) ..._activeCoins.map((c) => Positioned(left: c.position.dx - 25, top: c.position.dy - 25, child: const Text('🪙', style: TextStyle(fontSize: 45)))),
                if (_gameState == GameState.playing) Positioned(left: (_playerXPosition * constraints.maxWidth) - 40, bottom: 100, child: const Text('⛷️', style: TextStyle(fontSize: 80))),
              ],
            );
          }),

          // 4. UI Layer
          Positioned(top: 40, right: 20, child: IconButton(icon: const Icon(Icons.cancel, color: Colors.white70, size: 40), onPressed: () => Navigator.pop(context))),
          if (_gameState == GameState.playing) Positioned(top: 40, left: 20, child: Row(children: [
            _buildStatCard('Score: $_score', const Color(0xFF00D1B2)),
            const SizedBox(width: 10),
            _buildStatCard('${_timeRemainingSeconds ~/ 60}:${(_timeRemainingSeconds % 60).toString().padLeft(2, '0')}', Colors.redAccent),
          ])),

          if (_gameState == GameState.setup) _buildSetupScreen(),
          if (_gameState == GameState.gameOver) _buildGameOverScreen(),

          Align(alignment: Alignment.bottomCenter, child: Container(width: double.infinity, color: Colors.black54, padding: const EdgeInsets.symmetric(vertical: 8), child: const Text('⚠️ กรุณานั่งบนเก้าอี้ที่มีพนักพิงเพื่อความปลอดภัย', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 12)))),
        ],
      ),
    );
  }

  Widget _buildStatCard(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildSetupScreen() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24), margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20), border: Border.all(color: _isDistanceOk ? const Color(0xFF00D1B2) : Colors.red, width: 3)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Level 3: สกีท่านั่ง ⛷️", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF00D1B2))),
            const SizedBox(height: 15),
            if (_isStartingCountdown && _isDistanceOk) Text("$_setupCounter", style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: Color(0xFFFFB800)))
            else Icon(_isDistanceOk ? Icons.check_circle : Icons.warning_rounded, size: 60, color: _isDistanceOk ? Colors.green : Colors.orange),
            Text(_distanceHint, style: TextStyle(fontSize: 18, color: _isDistanceOk ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("กรุณานั่งห่างกล้อง 2 เมตร\nเอี้ยวตัวซ้าย-ขวาเพื่อเก็บเหรียญ", textAlign: TextAlign.center),
            const SizedBox(height: 20),
            DropdownButton<int>(value: _selectedMinutes, items: [1, 3, 5].map((v) => DropdownMenuItem(value: v, child: Text("$v นาที"))).toList(), onChanged: (v) => setState(() => _selectedMinutes = v!)),
            const SizedBox(height: 20),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _isDistanceOk ? const Color(0xFFFFB800) : Colors.grey, shape: const StadiumBorder()), onPressed: _isDistanceOk ? _startGame : null, child: const Text("เริ่มเกม!", style: TextStyle(fontSize: 20, color: Colors.white))),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOverScreen() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(30), decoration: BoxDecoration(color: Colors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("จบเกม! 🎉", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          Text("$_score คะแนน", style: const TextStyle(fontSize: 40, color: Color(0xFF00D1B2))),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("กลับเมนูหลัก")),
        ]),
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
    final paint = Paint()..color = isOk ? Colors.green.withOpacity(0.4) : Colors.red.withOpacity(0.4)..style = PaintingStyle.stroke..strokeWidth = 4;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.15, size.height * 0.2, size.width * 0.7, size.height * 0.5), paint);
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
    if (pose == null || imageSize == null) return;
    final paintLine = Paint()..color = const Color(0xFF00D1B2)..strokeWidth = 2.0;
    final paintPoint = Paint()..color = Colors.orange;
    final scaleX = size.width / imageSize!.width;
    final scaleY = size.height / imageSize!.height;
    Offset map(PoseLandmark lm) => Offset(size.width - (lm.x * scaleX), lm.y * scaleY);

    void drawLine(PoseLandmarkType t1, PoseLandmarkType t2) {
      final l1 = pose!.landmarks[t1]; final l2 = pose!.landmarks[t2];
      if (l1 != null && l2 != null) canvas.drawLine(map(l1), map(l2), paintLine);
    }
    drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
    drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
    drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
    for (var lm in pose!.landmarks.values) { if (lm.likelihood > 0.5) canvas.drawCircle(map(lm), 3, paintPoint); }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}