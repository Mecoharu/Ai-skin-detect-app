import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Skin Detector 🐱',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const DetectionScreen(),
    );
  }
}

enum SkinTone { brown, white, dark, scanning }

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isProcessing = false;

  SkinTone _currentTone = SkinTone.scanning;
  double _brightness = 0;
  double _redness = 0;

  
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  SkinTone _lastTone = SkinTone.scanning;


  static const _catAssets = {
    SkinTone.brown: 'assets/cats/cat1.jpg',
    SkinTone.white: 'assets/cats/cat2.jpg',
    SkinTone.dark:  'assets/cats/cat3.jpg',
  };

  static const _toneLabels = {
    SkinTone.brown: '🟤 brown',
    SkinTone.white: '⚪ white',
    SkinTone.dark:  '⚫ dark',
    SkinTone.scanning: '🔍 Aim ur camera..',
  };

  static const _toneColors = {
    SkinTone.brown: Color(0xFFA0632A),
    SkinTone.white: Color(0xFFE8C9A0),
    SkinTone.dark:  Color(0xFF5C3317),
    SkinTone.scanning: Colors.white24,
  };

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _initCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return;

    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    // Gunakan kamera belakang
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      back,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();

    if (!mounted) return;

 
    await _cameraController!.startImageStream(_onFrame);
    setState(() {});
  }


  void _onFrame(CameraImage frame) {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final int width = frame.width;
      final int height = frame.height;

      
      final int sampleSize = 20;
      final int startX = (width * 0.4).toInt();
      final int startY = (height * 0.4).toInt();
      final int endX = (width * 0.6).toInt();
      final int endY = (height * 0.6).toInt();

      // Ambil data Y (brightness) dan UV (warna)
      final yPlane = frame.planes[0];
      final uPlane = frame.planes[1];
      final vPlane = frame.planes[2];

      double sumR = 0, sumG = 0, sumB = 0;
      int count = 0;

      for (int y = startY; y < endY; y += 4) {
        for (int x = startX; x < endX; x += 4) {
          // Ambil Y (terang gelap) dan UV (warna) untuk piksel ini
          final yIndex = y * yPlane.bytesPerRow + x;
          if (yIndex >= yPlane.bytes.length) continue;
          final yVal = yPlane.bytes[yIndex];

        
          final uvIndex = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2);
          if (uvIndex >= uPlane.bytes.length || uvIndex >= vPlane.bytes.length) continue;
          final uVal = uPlane.bytes[uvIndex] - 128;
          final vVal = vPlane.bytes[uvIndex] - 128;

          
          final r = (yVal + 1.402 * vVal).clamp(0, 255).toInt();
          final g = (yVal - 0.344136 * uVal - 0.714136 * vVal).clamp(0, 255).toInt();
          final b = (yVal + 1.772 * uVal).clamp(0, 255).toInt();

          sumR += r;
          sumG += g;
          sumB += b;
          count++;
        }
      }

      if (count == 0) {
        _isProcessing = false;
        return;
      }

 
      final avgR = sumR / count;
      final avgG = sumG / count;
      final avgB = sumB / count;

      
      final brightness = (0.299 * avgR + 0.587 * avgG + 0.114 * avgB);

      
      final redness = avgR / (avgB + 1);

     
      final tone = _classifySkin(brightness, redness, avgR, avgG, avgB);

      if (mounted) {
        setState(() {
          _brightness = brightness;
          _redness = redness;
          _currentTone = tone;
        });
  
        if (tone != _lastTone && tone != SkinTone.scanning) {
          _lastTone = tone;
          _animController.forward(from: 0);
        }
      }
    } catch (_) {
    
    } finally {
      _isProcessing = false;
    }
  }


  SkinTone _classifySkin(double brightness, double redness,
      double r, double g, double b) {
    
    final isSkin = r > g && g > (b - 15) && redness > 1.1 && r > 80;

    if (!isSkin) return SkinTone.scanning;

    if (brightness > 160) return SkinTone.white;
    if (brightness > 95)  return SkinTone.brown;
    return SkinTone.dark;
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _cameraController?.value.isInitialized == true;
    final tone = _currentTone;
    final color = _toneColors[tone]!;
    final asset = _catAssets[tone];
    final label = _toneLabels[tone]!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          //  Preview kamera
          if (isReady)
            Positioned.fill(
              child: CameraPreview(_cameraController!),
            )
          else
            const Center(child: CircularProgressIndicator()),

          
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xCC000000),
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xDD000000),
                  ],
                  stops: [0.0, 0.2, 0.6, 1.0],
                ),
              ),
            ),
          ),

          // Lingkaran bidik 
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: tone == SkinTone.scanning
                      ? Colors.white54
                      : color,
                  width: 2.5,
                ),
              ),
              child: tone == SkinTone.scanning
                  ? const Icon(Icons.center_focus_weak,
                      color: Colors.white38, size: 40)
                  : null,
            ),
          ),

          
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text('🐱 Skin Detector',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'B:${_brightness.toStringAsFixed(0)} R:${_redness.toStringAsFixed(1)}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        
          Positioned(
            top: MediaQuery.of(context).size.height * 0.55,
            left: 0, right: 0,
            child: const Text(
              'Aim canera to skin body',
              style: TextStyle(color: Colors.white38, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),

        
          Positioned(
            bottom: 32, left: 16, right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Gambar kucing
                if (asset != null)
                  ScaleTransition(
                    scale: _scaleAnim,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.6),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(17),
                        child: Image.asset(
                          asset,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 160,
                            color: color.withOpacity(0.3),
                            child: const Icon(Icons.image_not_supported,
                                color: Colors.white38, size: 48),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Label warna kulit
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    color: tone == SkinTone.scanning
                        ? Colors.black54
                        : color.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: tone == SkinTone.scanning
                          ? Colors.white24
                          : color,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: tone == SkinTone.scanning
                          ? Colors.white54
                          : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}