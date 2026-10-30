import 'package:flutter/material.dart';
import 'package:ibnutify/core/theme/app_theme.dart';
import 'package:ibnutify/data/models/song_model.dart';
import 'package:ibnutify/presentation/widgets/common/song_artwork_widget.dart';

/// DynamicCoverWidget — Merender cover playlist estetik berbasis template HTML/CSS
/// secara 100% offline (DOM/Widget Flutter) tanpa me-generate file gambar JPG/PNG baru.
class DynamicCoverWidget extends StatelessWidget {
  final String? templateType; // 'minimal', 'dailymix', 'collage'
  final String? color; // Gradient ID or hex string
  final String? icon; // Icon key
  final String? title; // Custom title override
  final List<SongModel>? songs; // Songs list for collage / daily mix artwork
  final double size;
  final double borderRadius;
  final bool isPreview;

  const DynamicCoverWidget({
    super.key,
    this.templateType,
    this.color,
    this.icon,
    this.title,
    this.songs,
    this.size = 56.0,
    this.borderRadius = 8.0,
    this.isPreview = false,
  });

  // ── Color Presets Mapping (Dari ibnutify_library.html & DESIGN.md) ─────────

  static const Map<String, List<Color>> colorGradients = {
    'purple-indigo': [Color(0xFF6B21A8), Color(0xFF312E81)],
    'pink-rose': [Color(0xFFDB2777), Color(0xFF881337)],
    'green-emerald': [Color(0xFF10B981), Color(0xFF064E3B)],
    'blue-cyan': [Color(0xFF3B82F6), Color(0xFF164E63)],
    'orange-red': [Color(0xFFF97316), Color(0xFF7F1D1D)],
    'zinc-black': [Color(0xFF3F3F46), Color(0xFF091009)],
  };

  Gradient _parseGradient(String? colorKey) {
    if (colorKey != null && colorGradients.containsKey(colorKey)) {
      final colors = colorGradients[colorKey]!;
      return LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    // Default gradient jika null atau fallback
    return const LinearGradient(
      colors: [Color(0xFF6B21A8), Color(0xFF312E81)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  // ── Icon Presets Mapping (Dari ibnutify_library.html) ──────────────────────

  static IconData _parseIcon(String? iconKey) {
    switch (iconKey?.toLowerCase()) {
      case 'ph-infinity':
      case 'infinity':
        return Icons.all_inclusive_rounded;
      case 'ph-heart-straight':
      case 'ph-heart-fill':
      case 'heart':
        return Icons.favorite_rounded;
      case 'ph-star':
      case 'star':
        return Icons.star_rounded;
      case 'ph-music-notes':
      case 'music':
        return Icons.music_note_rounded;
      case 'ph-moon-stars':
      case 'moon':
        return Icons.nightlight_round;
      case 'ph-fire':
      case 'fire':
        return Icons.local_fire_department_rounded;
      case 'ph-coffee':
      case 'coffee':
        return Icons.free_breakfast_rounded;
      case 'ph-car-profile':
      case 'car':
        return Icons.directions_car_rounded;
      case 'ph-cloud-rain':
      case 'rain':
        return Icons.grain_rounded;
      case 'ph-headset':
      case 'headset':
        return Icons.headphones_rounded;
      default:
        return Icons.music_note_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = templateType ?? 'minimal';
    final displayTitle = title ?? '';

    Widget content;
    switch (type) {
      case 'dailymix':
        content = _buildDailyMixTemplate(displayTitle);
        break;
      case 'collage':
        content = _buildCollageTemplate(displayTitle);
        break;
      case 'minimal':
      default:
        content = _buildMinimalTemplate(displayTitle);
        break;
    }

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: isPreview
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: content,
    );
  }

  // ── 1. Minimalist / Iconic Template ───────────────────────────────────────

  Widget _buildMinimalTemplate(String displayTitle) {
    final gradient = _parseGradient(color);
    final iconData = _parseIcon(icon);
    final iconSize = isPreview ? size * 0.4 : size * 0.45;
    final fontSize = isPreview ? 22.0 : (size <= 64 ? 10.0 : 14.0);

    return Container(
      decoration: BoxDecoration(gradient: gradient),
      child: Stack(
        children: [
          // Icon di tengah
          Center(
            child: Icon(
              iconData,
              size: iconSize,
              color: Colors.white.withOpacity(0.85),
            ),
          ),

          // Title di sudut bawah kiri dengan shadow
          if (displayTitle.isNotEmpty)
            Positioned(
              left: isPreview ? 14 : 6,
              right: isPreview ? 14 : 6,
              bottom: isPreview ? 12 : 6,
              child: Text(
                displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  shadows: const [
                    Shadow(
                      color: Colors.black87,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 2. Daily Mix / Artist Photo Template ──────────────────────────────────

  Widget _buildDailyMixTemplate(String displayTitle) {
    final firstSong = songs?.isNotEmpty == true ? songs!.first : null;
    final fontSize = isPreview ? 22.0 : (size <= 64 ? 10.0 : 14.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background photo artis/album lokal
        if (firstSong != null)
          SongArtworkWidget(
            song: firstSong,
            size: size,
            borderRadius: 0,
            fit: BoxFit.cover,
          )
        else
          Container(
            decoration: BoxDecoration(gradient: _parseGradient(color)),
            child: const Icon(Icons.person_rounded, color: Colors.white38),
          ),

        // Gradient overlay dari hitam (bawah) ke transparan (atas)
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Color(0xEE091009),
                Color(0x66091009),
                Colors.transparent,
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),

        // Text typography bold
        if (displayTitle.isNotEmpty)
          Positioned(
            left: isPreview ? 14 : 6,
            right: isPreview ? 14 : 6,
            bottom: isPreview ? 12 : 6,
            child: Text(
              displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                height: 1.1,
                shadows: const [
                  Shadow(
                    color: Colors.black,
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── 3. Collage 2x2 Template ───────────────────────────────────────────────

  Widget _buildCollageTemplate(String displayTitle) {
    final songList = songs ?? [];
    final fontSize = isPreview ? 20.0 : (size <= 64 ? 9.0 : 13.0);

    Widget buildTile(int index) {
      if (index < songList.length) {
        return SongArtworkWidget(
          song: songList[index],
          size: size / 2,
          borderRadius: 0,
          fit: BoxFit.cover,
        );
      }
      return Container(
        color: AppColors.surfaceContainerHigh,
        child: const Icon(Icons.music_note_rounded, color: Colors.white24, size: 16),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 2x2 Grid
        Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: buildTile(0)),
                  Expanded(child: buildTile(1)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: buildTile(2)),
                  Expanded(child: buildTile(3)),
                ],
              ),
            ),
          ],
        ),

        // Gradient overlay
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Color(0xDD091009),
                Colors.transparent,
              ],
            ),
          ),
        ),

        // Title banner
        if (displayTitle.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black.withOpacity(0.4),
              padding: EdgeInsets.symmetric(
                horizontal: isPreview ? 10 : 4,
                vertical: isPreview ? 8 : 4,
              ),
              child: Text(
                displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
