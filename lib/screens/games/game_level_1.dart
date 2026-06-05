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

class GameLevel1 extends StatefulWidget {
  final int userStage;
  const GameLevel1({super.key, required this.userStage});

  @override
  State<GameLevel1> createState() => _GameLevel1State();
}

class _GameLevel1State extends State<GameLevel1> {
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

  bool _isDistanceOk = false;
  String _distanceHint = "กรุณามายืนหน้ากล้อง";
  Timer? _setupCountdownTimer;
  int _setupCounter = 3;
  bool _isStartingCountdown = false;
  
  Timer? _countdownTimer;
  bool _isWingsUp = false; 

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

    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.low, // ใช้ความละเอียดต่ำเหมือน Level 2 เพื่อความลื่นไหล
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
    LocalDB().insertScore(1, _score, 0.0, widget.userStage);
    DatabaseService().updateUnlockedLevel(2);
  }

  Future<void> _processImage(CameraImage image) async {
    _isProcessing = true;
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final camera = _cameraController!.description;
      final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
      
      final inputImageData = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: imageRotation,
        format: Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: inputImageData);

      // คำนวณ Size จริงของภาพตามการหมุน เหมือน Level 2
      bool isPortrait = imageRotation == InputImageRotation.rotation90deg || imageRotation == InputImageRotation.rotation270deg;
      Size absoluteImageSize = isPortrait 
          ? Size(image.height.toDouble(), image.width.toDouble()) 
          : Size(image.width.toDouble(), image.height.toDouble());

      if (mounted) setState(() { _imageSize = absoluteImageSize; });

      final poses = await _poseDetector.processImage(inputImage);
      
      if (poses.isNotEmpty) {
        final pose = poses.first;
        final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
        final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];

        if (leftShoulder != null && rightShoulder != null) {
          double sWidth = (leftShoulder.x - rightShoulder.x).abs() / image.width;
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

        // Logic ท่าปีกนก
        if (_gameState == GameState.playing) {
          final lW = pose.landmarks[PoseLandmarkType.leftWrist];
          final rW = pose.landmarks[PoseLandmarkType.rightWrist];
          final lS = pose.landmarks[PoseLandmarkType.leftShoulder];
          final rS = pose.landmarks[PoseLandmarkType.rightShoulder];

          if (lW != null && rW != null && lS != null && rS != null) {
            bool isUp = lW.y < lS.y - 30 && rW.y < rS.y - 30;
            bool isDown = lW.y > lS.y + 100 && rW.y > rS.y + 100;
            if (isUp && !_isWingsUp) {
              _isWingsUp = true;
            } else if (isDown && _isWingsUp) {
              setState(() { _isWingsUp = false; _score += 1; });
            }
          }
        }
      }
    } catch (e) {
      debugPrint("AI Error: $e");
    } finally {
      _isProcessing = false;
    }
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
                        CustomPaint(
                          painter: GameOverlayPainter(
                            pose: _currentPose,
                            imageSize: _imageSize,
                          ),
                        ),
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
                    _buildStatCard('Score: $_score', const Color(0xFF00D1B2)),
                    const SizedBox(width: 10),
                    _buildStatCard(_formattedTime, Colors.redAccent),
                  ],
                ),
              ),

            if (_gameState == GameState.playing)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 50),
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
                  child: Text(_isWingsUp ? "กดแขนลง 👇" : "ยกแขนขึ้น 👆", style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
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
            const Text("Level 1: ท่าปีกนก 🦅", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF00D1B2))),
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
              child: const Padding(padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12), child: Text("เริ่มเกม", style: TextStyle(fontSize: 22, color: Colors.white))),
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
            const Text("จบเกม! 🎉", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
            Text("$_score ครั้ง", style: const TextStyle(fontSize: 40, color: Color(0xFF00D1B2))),
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

// ✅ Painter ที่ปรับ Scale ให้ตรงเป๊ะเหมือน Level 2
class GameOverlayPainter extends CustomPainter {
  final Pose? pose;
  final Size? imageSize;

  GameOverlayPainter({this.pose, this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (pose != null && imageSize != null) {
      final paintLine = Paint()
        ..color = const Color(0xFF00D1B2).withOpacity(0.8)
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke;
      final paintPoint = Paint()
        ..color = const Color(0xFFFFB800)
        ..style = PaintingStyle.fill;

      final scaleX = size.width / imageSize!.width;
      final scaleY = size.height / imageSize!.height;

      // ฟังก์ชันแปลงพิกัด AI เป็นพิกัดหน้าจอ (แบบ Mirror)
      Offset mapPoint(PoseLandmark lm) {
        return Offset(size.width - (lm.x * scaleX), lm.y * scaleY);
      }

      void drawLine(PoseLandmarkType t1, PoseLandmarkType t2) {
        final l1 = pose!.landmarks[t1];
        final l2 = pose!.landmarks[t2];
        if (l1 != null && l2 != null && l1.likelihood > 0.5 && l2.likelihood > 0.5) {
          canvas.drawLine(mapPoint(l1), mapPoint(l2), paintLine);
        }
      }

      // วาดเส้นเชื่อมไหล่และแขน
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
      drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightWrist);
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftWrist);

      // วาดจุดเชื่อมต่อทั้งหมด
      for (final landmark in pose!.landmarks.values) {
        if (landmark.likelihood > 0.5) {
          canvas.drawCircle(mapPoint(landmark), 5, paintPoint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant GameOverlayPainter oldDelegate) => true;
}