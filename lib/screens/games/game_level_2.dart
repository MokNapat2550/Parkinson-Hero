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

class FallingItem {
  Offset position;
  double speed;
  String emoji;
  FallingItem(this.position, this.speed, this.emoji);
}

enum GameState { setup, playing, gameOver }

class GameLevel2 extends StatefulWidget {
  final int userStage;
  const GameLevel2({super.key, required this.userStage});

  @override
  State<GameLevel2> createState() => _GameLevel2State();
}

class _GameLevel2State extends State<GameLevel2> {
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

  // ✅ ระบบ Auto Countdown (เพิ่มใหม่)
  bool _isDistanceOk = false;
  String _distanceHint = "กรุณามายืนหน้ากล้อง";
  Timer? _setupCountdownTimer;
  int _setupCounter = 3;
  bool _isStartingCountdown = false;
  
  List<FallingItem> _activeItems = [];
  Timer? _gameLoop;
  Timer? _countdownTimer;
  final double _hitRadius = 70.0; 
  final Random _random = Random();
  final List<String> _emojis =  ['⭐'];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  // ✅ ฟังก์ชันคุมการนับถอยหลังอัตโนมัติ
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
            _startGame(); // เริ่มเกมทันทีเมื่อนับครบ
          }
        });
      } else {
        _stopSetupCountdown(); // หยุดนับถ้าถอยออกมาไม่พอหรือเดินเข้าใกล้เกินไป
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

  Future<void> _saveGameResult() async {
    try {
      await LocalDB().insertScore(2, _score, 0.0, widget.userStage);
      debugPrint("📊 [Level 2] บันทึกคะแนนสำเร็จ: $_score แต้ม");
    } catch (e) {
      debugPrint("❌ [Level 2] บันทึกผิดพลาด: $e");
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

    _cameraController?.startImageStream((CameraImage image) {
      if (!_isProcessing) {
        _processImage(image);
      }
    });
  }

  void _startGame() {
    _stopSetupCountdown(); // ล้าง Timer นับถอยหลัง

    setState(() {
      _score = 0;
      _timeRemainingSeconds = _selectedMinutes * 60;
      _activeItems.clear();
      _gameState = GameState.playing;
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
        for (int i = 0; i < _activeItems.length; i++) {
          _activeItems[i].position = Offset(
            _activeItems[i].position.dx,
            _activeItems[i].position.dy + _activeItems[i].speed,
          );
        }
        if (_canvasSize != Size.zero) {
          _activeItems.removeWhere((item) => item.position.dy > _canvasSize.height + 50);
        }
        if (_random.nextDouble() < 0.05 && _activeItems.length < 6) {
          _spawnItem();
        }
      });
    });
  }

  void _endGame() {
    _countdownTimer?.cancel();
    _gameLoop?.cancel();
    setState(() {
      _gameState = GameState.gameOver;
      _activeItems.clear();
    });
    _saveGameResult();
  }

  void _onGameComplete(BuildContext context) {
    DatabaseService().updateUnlockedLevel(3); 
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ปลดล็อกด่าน 3 แล้ว 🎉'), backgroundColor: Colors.green),
    );
    Navigator.pop(context);
  }

  void _spawnItem() {
    if (_canvasSize == Size.zero) return;
    double startX = 50 + _random.nextDouble() * (_canvasSize.width - 100);
    double speed = 4 + _random.nextDouble() * 6; 
    String emoji = _emojis[_random.nextInt(_emojis.length)];
    _activeItems.add(FallingItem(Offset(startX, -50), speed, emoji));
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
      
      bool isPortrait = imageRotation == InputImageRotation.rotation90deg || imageRotation == InputImageRotation.rotation270deg;
      Size absoluteImageSize = isPortrait 
          ? Size(image.height.toDouble(), image.width.toDouble()) 
          : Size(image.width.toDouble(), image.height.toDouble());

      if (mounted) setState(() { _imageSize = absoluteImageSize; });

      final poses = await _poseDetector.processImage(inputImage);
      
      if (poses.isNotEmpty) {
        final pose = poses.first;

        // 🔍 [AI Distance Check Logic]
        final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
        final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];

        if (leftShoulder != null && rightShoulder != null) {
          double sWidth = (leftShoulder.x - rightShoulder.x).abs() / image.width;
          if (mounted) {
            setState(() {
              // 📌 0.25 คือระยะห่างประมาณ 2 เมตร
              if (sWidth < 0.25) { 
                _isDistanceOk = true;
                _distanceHint = "ระยะห่างเหมาะสมแล้ว ✅";
                // ✅ เริ่มนับถอยหลังอัตโนมัติเมื่ออยู่ในหน้า Setup
                if (!_isStartingCountdown && _gameState == GameState.setup) {
                  _startSetupCountdown();
                }
              } else {
                _isDistanceOk = false;
                _distanceHint = "กรุณาถอยห่างจากกล้องอีกนิด";
                _stopSetupCountdown(); // ยกเลิกการนับหากระยะไม่ได้
              }
            });
          }
        }

        if (mounted) setState(() { _currentPose = pose; });

        // 🎮 [Collision Check] - ทำงานเฉพาะตอนเล่น
        if (_gameState == GameState.playing) {
          List<PoseLandmark> touchPoints = [];
          final pointsToCheck = [
            PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
            PoseLandmarkType.leftIndex, PoseLandmarkType.rightIndex,
          ];
          for (var type in pointsToCheck) {
            final lm = pose.landmarks[type];
            if (lm != null && lm.likelihood > 0.5) touchPoints.add(lm);
          }
          _checkCollision(touchPoints);
        }
      } else {
        if (mounted) setState(() { _currentPose = null; });
      }
    } catch (e) {
      debugPrint("AI Error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  void _checkCollision(List<PoseLandmark> touchPoints) {
    if (_activeItems.isEmpty || _imageSize == null || _canvasSize == Size.zero) return;
    
    final scaleX = _canvasSize.width / _imageSize!.width; 
    final scaleY = _canvasSize.height / _imageSize!.height;

    List<FallingItem> hitItems = []; 
    for (var point in touchPoints) {
      double mappedX = _canvasSize.width - (point.x * scaleX); 
      double mappedY = point.y * scaleY;

      for (var item in _activeItems) {
        double distance = sqrt(pow(mappedX - item.position.dx, 2) + pow(mappedY - item.position.dy, 2));
        if (distance < _hitRadius) {
          hitItems.add(item); 
        }
      }
    }

    if (hitItems.isNotEmpty) {
      setState(() {
        for (var item in hitItems) {
          _activeItems.remove(item);
          _score += 1;
        }
      });
    }
  }

  @override
  void dispose() {
    _setupCountdownTimer?.cancel();
    _countdownTimer?.cancel();
    _gameLoop?.cancel(); 
    _cameraController?.stopImageStream();
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
                      if (_canvasSize != constraints.biggest) {
                        setState(() { _canvasSize = constraints.biggest; });
                      }
                    });

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_cameraController!),
                        if (_gameState == GameState.setup) CustomPaint(painter: DistanceGuidePainter(isOk: _isDistanceOk)),
                        CustomPaint(
                          painter: GameOverlayPainter(
                            activeItems: _activeItems,
                            pose: _currentPose,
                            imageSize: _imageSize,
                            showItems: _gameState == GameState.playing, 
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            Positioned(
              top: 20, right: 20,
              child: IconButton(
                icon: const Icon(Icons.cancel, color: Colors.white70, size: 40),
                onPressed: () => Navigator.pop(context),
              ),
            ),

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
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95), 
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _isDistanceOk ? const Color(0xFF00D1B2) : Colors.red, width: 3)
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Level 2: เก็บดาว 🌟", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF00D1B2))),
            const SizedBox(height: 10),
            
            // ✅ แสดงตัวเลขถอยหลังเมื่อพร้อม
            if (_isStartingCountdown && _isDistanceOk)
               Text(
                "$_setupCounter",
                style: const TextStyle(fontSize: 100, fontWeight: FontWeight.bold, color: Color(0xFFFFB800)),
              )
            else
              Icon(
                _isDistanceOk ? Icons.check_circle : Icons.warning_rounded, 
                size: 60, 
                color: _isDistanceOk ? const Color(0xFF00D1B2) : Colors.orange
              ),
            
            const SizedBox(height: 10),
            Text(
              _distanceHint, 
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: _isDistanceOk ? Colors.green : Colors.red, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 10),
            const Text("กรุณาถอยห่าง 2 เมตร เพื่อความปลอดภัยในการเอื้อมแขน", textAlign: TextAlign.center, style: TextStyle(fontSize: 14)),
            const SizedBox(height: 15),
            DropdownButton<int>(
              value: _selectedMinutes,
              items: [1, 3, 5].map((int val) => DropdownMenuItem(value: val, child: Text("$val นาที"))).toList(),
              onChanged: (val) => setState(() => _selectedMinutes = val!),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isDistanceOk ? const Color(0xFFFFB800) : Colors.grey, 
                shape: const StadiumBorder()
              ),
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
            const Text("หมดเวลา! 🎉", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
            Text("$_score คะแนน", style: const TextStyle(fontSize: 40, color: Color(0xFF00D1B2))),
            const SizedBox(height: 30),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(onPressed: () => _onGameComplete(context), child: const Text("กลับเมนู")),
                const SizedBox(width: 15),
                ElevatedButton(onPressed: () {
                  setState(() { _gameState = GameState.setup; });
                }, child: const Text("เล่นอีกครั้ง")),
              ],
            )
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
    final paint = Paint()
      ..color = isOk ? Colors.green.withOpacity(0.5) : Colors.red.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.1, size.height * 0.1, size.width * 0.8, size.height * 0.8), paint);
  }
  @override
  bool shouldRepaint(CustomPainter old) => true;
}

class GameOverlayPainter extends CustomPainter {
  final List<FallingItem> activeItems;
  final Pose? pose;
  final Size? imageSize;
  final bool showItems;

  GameOverlayPainter({required this.activeItems, this.pose, this.imageSize, required this.showItems});

  @override
  void paint(Canvas canvas, Size size) {
    if (showItems) {
      for (var item in activeItems) {
        final textPainter = TextPainter(
          text: TextSpan(text: item.emoji, style: const TextStyle(fontSize: 50)),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(item.position.dx - 25, item.position.dy - 25));
      }
    }

    if (pose != null && imageSize != null) {
      final paintLine = Paint()..color = const Color(0xFF00D1B2).withOpacity(0.8)..strokeWidth = 4.0..style = PaintingStyle.stroke;
      final paintPoint = Paint()..color = const Color(0xFFFFB800)..style = PaintingStyle.fill;
      final scaleX = size.width / imageSize!.width;
      final scaleY = size.height / imageSize!.height;

      Offset mapPoint(PoseLandmark lm) => Offset(size.width - (lm.x * scaleX), lm.y * scaleY);

      void drawLine(PoseLandmarkType t1, PoseLandmarkType t2) {
        final l1 = pose!.landmarks[t1];
        final l2 = pose!.landmarks[t2];
        if (l1 != null && l2 != null && l1.likelihood > 0.5 && l2.likelihood > 0.5) {
          canvas.drawLine(mapPoint(l1), mapPoint(l2), paintLine);
        }
      }

      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
      drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightWrist);
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftWrist);

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