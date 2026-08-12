import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

/// OsmMapWidget — peta OpenStreetMap dengan overlay GPS route.
///
/// Menggunakan tile CDN OSM gratis (tile.openstreetmap.org) — tidak perlu API key.
/// Tile di-cache otomatis oleh Flutter's Image widget (NetworkImage + LRU cache).
/// Jika offline, tile gagal load → background fallback gelap, route tetap tampil.
///
/// Attribution: © OpenStreetMap contributors (wajib sesuai ODbL license).
class OsmMapWidget extends StatelessWidget {
  final List<LatLngPoint> points;
  final double height;
  final bool showLiveIndicator;
  final bool isLive; // true = workout aktif, false = history view

  const OsmMapWidget({
    super.key,
    required this.points,
    this.height = 220,
    this.showLiveIndicator = false,
    this.isLive = false,
  });

  // ── Tile Math ───────────────────────────────────────────────────────────────

  static const int _tileSize = 256;

  /// Konversi longitude ke pixel-x global pada zoom tertentu.
  static double _lngToPixel(double lng, int zoom) =>
      (lng + 180) / 360 * (1 << zoom) * _tileSize;

  /// Konversi latitude ke pixel-y global pada zoom tertentu (Mercator).
  static double _latToPixel(double lat, int zoom) {
    final latRad = lat * math.pi / 180;
    return (1 -
            math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
        2 *
        (1 << zoom) *
        _tileSize;
  }

  /// Hitung zoom optimal agar seluruh route muat di viewport dengan padding.
  static int _bestZoom({
    required double latRange,
    required double lngRange,
    required double viewW,
    required double viewH,
  }) {
    if (latRange == 0 && lngRange == 0) return 17; // single point / belum ada route
    for (int z = 18; z >= 5; z--) {
      final pixW = lngRange / 360 * (1 << z) * _tileSize;
      final pixH = latRange / 180 * (1 << z) * _tileSize;
      if (pixW < viewW * 0.65 && pixH < viewH * 0.65) return z;
    }
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewW = constraints.maxWidth;
        final viewH = height;

        // ── Hitung bounding box ──────────────────────────────────────────
        double centerLat, centerLng;
        int zoom;

        if (points.isEmpty) {
          // Belum ada GPS — tampilkan peta Indonesia default
          centerLat = -6.2; // Jakarta
          centerLng = 106.8;
          zoom = 12;
        } else {
          double minLat = points.first.lat, maxLat = points.first.lat;
          double minLng = points.first.lng, maxLng = points.first.lng;
          for (final p in points) {
            if (p.lat < minLat) minLat = p.lat;
            if (p.lat > maxLat) maxLat = p.lat;
            if (p.lng < minLng) minLng = p.lng;
            if (p.lng > maxLng) maxLng = p.lng;
          }
          final latRange = maxLat - minLat;
          final lngRange = maxLng - minLng;

          centerLat = (minLat + maxLat) / 2;
          centerLng = (minLng + maxLng) / 2;

          // Saat live tracking + baru mulai (< 3 titik), zoom ke posisi user
          if (isLive && points.length < 3) {
            centerLat = points.last.lat;
            centerLng = points.last.lng;
            zoom = 17;
          } else {
            zoom = _bestZoom(
              latRange: latRange,
              lngRange: lngRange,
              viewW: viewW,
              viewH: viewH,
            );
          }
        }

        // ── Hitung posisi pixel center di tile system ────────────────────
        final centerPixX = _lngToPixel(centerLng, zoom);
        final centerPixY = _latToPixel(centerLat, zoom);

        // Top-left pixel dari viewport
        final topLeftPixX = centerPixX - viewW / 2;
        final topLeftPixY = centerPixY - viewH / 2;

        // Tile index awal
        final startTileX = (topLeftPixX / _tileSize).floor();
        final startTileY = (topLeftPixY / _tileSize).floor();

        // Offset piksel di dalam tile pertama
        final tileOffsetX = topLeftPixX - startTileX * _tileSize;
        final tileOffsetY = topLeftPixY - startTileY * _tileSize;

        // Jumlah tile yang dibutuhkan
        final tilesX = (viewW / _tileSize).ceil() + 2;
        final tilesY = (viewH / _tileSize).ceil() + 2;

        // ── Konversi GPS point ke koordinat layar ────────────────────────
        Offset gpsToScreen(LatLngPoint p) {
          final px = _lngToPixel(p.lng, zoom) - topLeftPixX;
          final py = _latToPixel(p.lat, zoom) - topLeftPixY;
          return Offset(px, py);
        }

        final screenPoints = points.map(gpsToScreen).toList();

        return ClipRect(
          child: SizedBox(
            height: viewH,
            width: viewW,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // ── Background fallback ─────────────────────────────────
                Container(color: const Color(0xFF1A1F1A)),

                // ── OSM Tile Grid ───────────────────────────────────────
                Positioned.fill(
                  child: Stack(
                    children: [
                      for (int tx = 0; tx < tilesX; tx++)
                        for (int ty = 0; ty < tilesY; ty++)
                          Positioned(
                            left: tx * _tileSize.toDouble() - tileOffsetX,
                            top: ty * _tileSize.toDouble() - tileOffsetY,
                            width: _tileSize.toDouble(),
                            height: _tileSize.toDouble(),
                            child: _OsmTile(
                              z: zoom,
                              x: startTileX + tx,
                              y: startTileY + ty,
                            ),
                          ),
                    ],
                  ),
                ),

                // ── Dark overlay agar teks tile tidak terlalu terang ────
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                    ),
                  ),
                ),

                // ── GPS Route Painter ───────────────────────────────────
                if (screenPoints.length > 1)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _OsmRoutePainter(screenPoints: screenPoints),
                    ),
                  ),

                // ── Single-point dot (belum cukup track) ───────────────
                if (screenPoints.length == 1)
                  Positioned(
                    left: screenPoints.first.dx - 10,
                    top: screenPoints.first.dy - 10,
                    child: _LivePositionDot(pulse: isLive),
                  ),

                // ── Current position dot on top of route ────────────────
                if (screenPoints.length > 1)
                  Positioned(
                    left: screenPoints.last.dx - 10,
                    top: screenPoints.last.dy - 10,
                    child: _LivePositionDot(pulse: isLive),
                  ),

                // ── Status bar bawah ────────────────────────────────────
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.65),
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        if (showLiveIndicator) ...[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${points.length} titik GPS',
                            style: const TextStyle(
                              color: AppColors.onSurface,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else
                          Row(
                            children: [
                              const Icon(Icons.my_location_rounded,
                                  color: AppColors.primary, size: 13),
                              const SizedBox(width: 4),
                              Text(
                                '${points.length} titik GPS',
                                style: const TextStyle(
                                  color: AppColors.onSurface,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        const Spacer(),
                        // OSM Attribution (WAJIB sesuai lisensi ODbL)
                        const Text(
                          '© OpenStreetMap',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── OSM Tile Widget ────────────────────────────────────────────────────────────

/// Single tile dari OpenStreetMap CDN.
/// Flutter's Image widget auto-cache di memory (PaintingBinding.imageCache).
class _OsmTile extends StatelessWidget {
  final int z, x, y;
  const _OsmTile({required this.z, required this.x, required this.y});

  @override
  Widget build(BuildContext context) {
    // Clamp ke valid tile range
    final maxTile = (1 << z) - 1;
    if (x < 0 || y < 0 || x > maxTile || y > maxTile) {
      return Container(color: const Color(0xFF1A1F1A));
    }

    // Gunakan salah satu dari 3 subserver OSM (a/b/c) untuk load balancing
    final sub = ['a', 'b', 'c'][x % 3];
    final url = 'https://$sub.tile.openstreetmap.org/$z/$x/$y.png';

    return Image.network(
      url,
      width: 256,
      height: 256,
      fit: BoxFit.cover,
      // Tile gagal load (offline) → background gelap, tidak crash
      errorBuilder: (_, __, ___) =>
          Container(color: const Color(0xFF181D18)),
      // Placeholder saat loading
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(color: const Color(0xFF1C211C));
      },
      // Cache key unik per tile
      cacheWidth: 256,
      cacheHeight: 256,
      headers: const {
        'User-Agent': 'IbnuTify/1.0 (Flutter; fitness app)',
      },
    );
  }
}

// ── Route Painter (diatas tile) ────────────────────────────────────────────────

class _OsmRoutePainter extends CustomPainter {
  final List<Offset> screenPoints;
  const _OsmRoutePainter({required this.screenPoints});

  @override
  void paint(Canvas canvas, Size size) {
    if (screenPoints.length < 2) return;

    // ── Shadow/glow ──────────────────────────────────────────────────────
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // ── Glow layer ────────────────────────────────────────────────────────
    final glowPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // ── Main line ─────────────────────────────────────────────────────────
    final linePaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(screenPoints.first.dx, screenPoints.first.dy);
    for (final pt in screenPoints.skip(1)) {
      path.lineTo(pt.dx, pt.dy);
    }

    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);

    // ── Start marker ─────────────────────────────────────────────────────
    final start = screenPoints.first;
    canvas.drawCircle(start, 5,
        Paint()..color = Colors.white.withOpacity(0.85));
    canvas.drawCircle(start, 5,
        Paint()
          ..color = AppColors.primary.withOpacity(0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_OsmRoutePainter old) {
    if (old.screenPoints.length != screenPoints.length) return true;
    if (screenPoints.isEmpty) return false;
    final ol = old.screenPoints.last;
    final nl = screenPoints.last;
    return ol.dx != nl.dx || ol.dy != nl.dy;
  }
}

// ── Live Position Dot (animated) ──────────────────────────────────────────────

/// Dot posisi user — beranimasi pulse saat live, statis saat history.
class _LivePositionDot extends StatefulWidget {
  final bool pulse;
  const _LivePositionDot({this.pulse = false});

  @override
  State<_LivePositionDot> createState() => _LivePositionDotState();
}

class _LivePositionDotState extends State<_LivePositionDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _scaleAnim =
        Tween<double>(begin: 0.5, end: 1.5).animate(CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOut,
    ));
    _fadeAnim =
        Tween<double>(begin: 0.7, end: 0.0).animate(CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOut,
    ));
    if (widget.pulse) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulse ring (hanya saat live)
          if (widget.pulse)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Transform.scale(
                scale: _scaleAnim.value,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary
                        .withOpacity(_fadeAnim.value * 0.6),
                  ),
                ),
              ),
            ),
          // Outer ring
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.25),
              border: Border.all(
                  color: AppColors.primary.withOpacity(0.7), width: 1.5),
            ),
          ),
          // Inner solid dot
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
            ),
          ),
          // White center
          Container(
            width: 3,
            height: 3,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
