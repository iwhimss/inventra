import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:inventra_app/core/theme/app_theme.dart';

/// Tam ekran barkod tarayıcı sayfası.
/// Ortada tarama çerçevesi, animasyonlu scan çizgisi ve 1.5s debounce içerir.
class BarcodeScannerPage extends StatefulWidget {
  final void Function(String barcode) onDetected;

  const BarcodeScannerPage({required this.onDetected, super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage>
    with TickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController();
  late final AnimationController _scanLineController;
  late final Animation<double> _scanLineAnim;

  // Onay bekleme: bir barkod algılanınca hemen kabul edilmez, aynı barkod
  // kesintisiz algılanmaya devam ederse kabul edilir.
  late final AnimationController _confirmController;
  String? _candidateCode;

  // Bekçi zamanlayıcı: mobile_scanner, barkod artık görünmediğinde onDetect'i
  // her zaman boş listeyle çağırmayabilir (bazı platformlarda hiç çağırmaz).
  // Bu yüzden iptal kararını yalnızca gelen callback'lere bağlı bırakmıyoruz —
  // adayın en son ne zaman GERÇEKTEN görüldüğünü bağımsız olarak takip edip,
  // belirli bir süre tazelenmezse otomatik iptal ediyoruz.
  //
  // Eşik SABİT değil — kameranın o anki gerçek algılama ritmine göre canlı
  // hesaplanır (son birkaç algılama arası boşluğun ortalamasının 3 katı).
  // Sabit bir milisaniye değeri cihazdan cihaza değişen kamera/analiz hızına
  // göre ya çok sıkı (yanlış-pozitif iptal) ya da onay süresine çok yakın
  // (gerçek kaldırmayı yakalayamama) oluyordu.
  DateTime? _lastSeenAt;
  Timer? _watchdog;
  final List<int> _recentGapsMs = [];
  static const _minThreshold = Duration(milliseconds: 250);
  static const _maxThreshold = Duration(milliseconds: 500); // 700ms onaydan her zaman güvenli marj

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scanLineAnim = CurvedAnimation(
      parent: _scanLineController,
      curve: Curves.easeInOut,
    );
    _confirmController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _confirmScan();
      });
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _confirmController.dispose();
    _watchdog?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) {
      _cancelCandidate();
      return;
    }
    final code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) {
      _cancelCandidate();
      return;
    }

    final now = DateTime.now();
    if (_lastSeenAt != null) {
      _recentGapsMs.add(now.difference(_lastSeenAt!).inMilliseconds);
      if (_recentGapsMs.length > 5) _recentGapsMs.removeAt(0);
    }
    _lastSeenAt = now;
    _watchdog ??= Timer.periodic(const Duration(milliseconds: 100), (_) => _checkWatchdog());

    if (_candidateCode != code) {
      setState(() => _candidateCode = code);
      _confirmController
        ..stop()
        ..reset()
        ..forward();
      _recentGapsMs.clear(); // yeni aday için geçmiş ritim verisi geçersiz
    }
  }

  void _checkWatchdog() {
    if (_candidateCode == null || _lastSeenAt == null) return;
    final avgGapMs = _recentGapsMs.isEmpty
        ? 150 // henüz veri yoksa makul bir varsayılan
        : _recentGapsMs.reduce((a, b) => a + b) ~/ _recentGapsMs.length;
    final thresholdMs = (avgGapMs * 3).clamp(
      _minThreshold.inMilliseconds,
      _maxThreshold.inMilliseconds,
    );
    if (DateTime.now().difference(_lastSeenAt!) > Duration(milliseconds: thresholdMs)) {
      _cancelCandidate();
    }
  }

  void _cancelCandidate() {
    if (_candidateCode == null) return;
    _confirmController.stop();
    _confirmController.reset();
    _watchdog?.cancel();
    _watchdog = null;
    _lastSeenAt = null;
    _recentGapsMs.clear();
    setState(() => _candidateCode = null);
  }

  void _confirmScan() {
    final code = _candidateCode;
    if (code == null) return;
    Navigator.of(context).pop();
    widget.onDetected(code);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    // Tarama penceresi: ekran ortasında %65 genişlik × %28 yükseklik
    final frameW = size.width * 0.65;
    final frameH = size.height * 0.28;
    final frameLeft = (size.width - frameW) / 2;
    final frameTop = (size.height - frameH) / 2 - 20;
    final scanWindow = Rect.fromLTWH(frameLeft, frameTop, frameW, frameH);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            fit: BoxFit.cover,
            scanWindow: scanWindow,
            errorBuilder: (context, error, child) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Kamera Hatası: ${error.errorCode.name}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.errorDetails?.message ?? '',
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _controller.start(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tekrar Dene'),
                  ),
                ],
              ),
            ),
            placeholderBuilder: (p0, p1) => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.secondaryAccent),
                  SizedBox(height: 16),
                  Text(
                    'Kamera başlatılıyor...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            onDetect: _onDetect,
          ),

          // Koyu maske — tarama çerçevesinin dışı
          _ScanOverlay(scanWindow: scanWindow),

          // Animasyonlu scan çizgisi
          AnimatedBuilder(
            animation: _scanLineAnim,
            builder: (context, child) {
              final lineY =
                  scanWindow.top + scanWindow.height * _scanLineAnim.value;
              return Positioned(
                left: scanWindow.left + 8,
                top: lineY,
                child: Container(
                  width: scanWindow.width - 16,
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        AppTheme.primaryAccent.withOpacity(0.9),
                        Colors.transparent,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              );
            },
          ),

          // Üst bar: kapat + kamera çevir
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(
                        Icons.flip_camera_ios,
                        color: Colors.white,
                      ),
                      onPressed: () => _controller.switchCamera(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Alt açıklama metni / onay bekleme göstergesi
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedBuilder(
                animation: _confirmController,
                builder: (context, child) {
                  final candidate = _candidateCode;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: candidate == null
                        ? const Text(
                            'Barkodu çerçeve içine yerleştirin',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  value: _confirmController.value,
                                  strokeWidth: 2,
                                  color: AppTheme.primaryAccent,
                                  backgroundColor: Colors.white24,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Taranıyor: $candidate',
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ],
                          ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarama çerçevesi dışını karartır, köşelere L-şekli işaret çizer.
class _ScanOverlay extends StatelessWidget {
  final Rect scanWindow;

  const _ScanOverlay({required this.scanWindow});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _OverlayPainter(scanWindow: scanWindow));
  }
}

class _OverlayPainter extends CustomPainter {
  final Rect scanWindow;

  _OverlayPainter({required this.scanWindow});

  @override
  void paint(Canvas canvas, Size size) {
    final maskPaint = Paint()..color = Colors.black.withOpacity(0.62);

    // Çerçeve dışını karart (4 dikdörtgen)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, scanWindow.top),
      maskPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        scanWindow.bottom,
        size.width,
        size.height - scanWindow.bottom,
      ),
      maskPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, scanWindow.top, scanWindow.left, scanWindow.height),
      maskPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        scanWindow.right,
        scanWindow.top,
        size.width - scanWindow.right,
        scanWindow.height,
      ),
      maskPaint,
    );

    // Köşe L işaretleri
    const cornerLen = 22.0;
    const cornerW = 3.5;
    final cornerPaint = Paint()
      ..color = AppTheme.primaryAccent
      ..strokeWidth = cornerW
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    void drawCorner(Offset origin, double dx, double dy) {
      canvas.drawLine(origin, origin + Offset(dx, 0), cornerPaint);
      canvas.drawLine(origin, origin + Offset(0, dy), cornerPaint);
    }

    drawCorner(scanWindow.topLeft, cornerLen, cornerLen);
    drawCorner(scanWindow.topRight, -cornerLen, cornerLen);
    drawCorner(scanWindow.bottomLeft, cornerLen, -cornerLen);
    drawCorner(scanWindow.bottomRight, -cornerLen, -cornerLen);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) =>
      oldDelegate.scanWindow != scanWindow;
}
