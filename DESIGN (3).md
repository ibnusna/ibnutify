---
name: IbnuTify
colors:
  surface: '#0e150e'
  surface-dim: '#0e150e'
  surface-bright: '#333b33'
  surface-container-lowest: '#091009'
  surface-container-low: '#161d16'
  surface-container: '#1a211a'
  surface-container-high: '#242c24'
  surface-container-highest: '#2f372e'
  on-surface: '#dde5d9'
  on-surface-variant: '#bccbb9'
  inverse-surface: '#dde5d9'
  inverse-on-surface: '#2b322a'
  outline: '#869585'
  outline-variant: '#3d4a3d'
  surface-tint: '#53e076'
  primary: '#53e076'
  on-primary: '#003914'
  primary-container: '#1db954'
  on-primary-container: '#004118'
  inverse-primary: '#006e2d'
  secondary: '#c8c6c5'
  on-secondary: '#313030'
  secondary-container: '#4a4949'
  on-secondary-container: '#bab8b7'
  tertiary: '#ffb3b3'
  on-tertiary: '#680114'
  tertiary-container: '#ff767b'
  on-tertiary-container: '#730a1b'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#72fe8f'
  primary-fixed-dim: '#53e076'
  on-primary-fixed: '#002108'
  on-primary-fixed-variant: '#005320'
  secondary-fixed: '#e5e2e1'
  secondary-fixed-dim: '#c8c6c5'
  on-secondary-fixed: '#1c1b1b'
  on-secondary-fixed-variant: '#474646'
  tertiary-fixed: '#ffdad9'
  tertiary-fixed-dim: '#ffb3b3'
  on-tertiary-fixed: '#400009'
  on-tertiary-fixed-variant: '#881d28'
  background: '#0e150e'
  on-background: '#dde5d9'
  surface-variant: '#2f372e'
typography:
  display-lg:
    fontFamily: beVietnamPro
    fontSize: 32px
    fontWeight: '800'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: beVietnamPro
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.01em
  title-sm:
    fontFamily: beVietnamPro
    fontSize: 16px
    fontWeight: '700'
    lineHeight: 24px
  body-md:
    fontFamily: beVietnamPro
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-sm:
    fontFamily: beVietnamPro
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0.01em
  metadata:
    fontFamily: beVietnamPro
    fontSize: 11px
    fontWeight: '400'
    lineHeight: 14px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 4px
  xs: 8px
  sm: 12px
  md: 16px
  lg: 24px
  xl: 32px
  gutter: 16px
  margin: 16px
---

## Brand & Style
The brand personality of the design system is immersive, energetic, and focused. It is designed to recede into the background, allowing the album art and music metadata to remain the focal point of the user experience. By utilizing a high-contrast dark aesthetic, it evokes the feeling of a premium, late-night listening session.

The visual style follows a **Modern / Minimalist** approach. It relies on clean lines, significant negative space despite the dark palette, and a "content-first" hierarchy. The interface avoids unnecessary decoration, using color only to indicate interactivity or current state (e.g., active playback).

## Colors
The color palette of this design system is rooted in high-contrast functionality. The "Pure Black" primary background ensures that OLED screens achieve perfect deep blacks, while the "Dark Grey" secondary background is used to define surfaces and containers. 

The "Spotify Green" accent is used sparingly for primary actions, progress indicators, and active states. Primary text is pure white for maximum legibility, while secondary metadata and inactive icons use "Light Grey" to create a clear visual hierarchy.

## Typography
This design system utilizes **beVietnamPro** to achieve a contemporary, entertainment-focused aesthetic. The typographic scale prioritizes bold, heavy-weight headings to anchor screens, especially in playlist views and artist profiles. 

Information density is managed by using the "Light Grey" secondary color for all body and label text that isn't the primary focus. Metadata—such as timestamps, bitrates, or track numbers—uses the smallest tier of the scale with slightly increased letter spacing to maintain clarity on mobile displays.

## Layout & Spacing
The layout philosophy is based on a **Fluid Grid** model optimized for Android handheld devices. Content spans the width of the screen with fixed 16px horizontal margins. 

The spacing rhythm follows a 4px baseline, with 8px and 16px being the primary increments for component grouping. List items (tracks) use a consistent 16px vertical padding to ensure touch targets are accessible. Safe areas are strictly observed at the bottom of the screen to account for the persistent playback bar and system navigation.

## Elevation & Depth
In this design system, depth is communicated through **Tonal Layers** and **Subtle Gradients** rather than traditional shadows. 

The lowest layer is Pure Black (#121212). Elevated elements, such as cards or secondary sections, use Dark Grey (#181818). To create a sense of atmosphere, a subtle linear gradient (30% opacity of the accent color or album art dominant color) may be applied to the top of playlist pages, fading into the Pure Black background. This "smoke" effect provides depth without cluttering the UI with heavy drop shadows.

## Shapes
The shape language of the design system is approachable and modern. It uses a **Rounded** corner strategy. 

Standard components like album art thumbnails and cards utilize an 8px (0.5rem) radius. Larger interactive containers or prominent call-to-action sections may use up to a 12px radius. Playback control buttons (Play/Pause) are strictly pill-shaped (fully rounded) to differentiate them from content containers and emphasize their interactive nature.

## Components

### Buttons
- **Primary Action:** Pill-shaped, Spotify Green background with black text. Used for "Shuffle Play."
- **Secondary Action:** Ghost style with white border or simple white text.
- **Playback Controls:** Clean, stroke-based icons. The Play/Pause button is the largest, often housed in a solid white or green circle.

### Lists & Items
- **Track Rows:** A horizontal layout with a small 48x48px thumbnail, followed by a vertical stack of Title (White) and Artist (Grey).
- **Active State:** The Title text changes to Spotify Green, and a small animated equalizer icon appears to the left.

### Cards
- **Album/Artist Cards:** Square aspect ratio for imagery with an 8px corner radius. Title text is placed directly below the image, left-aligned.

### Persistent Playback Bar
- A floating or bottom-anchored bar using Dark Grey (#181818). It includes a miniature album art thumb, track info, and a play/pause toggle. A 2px thin progress bar is pinned to the very top of this component.

### Inputs & Search
- **Search Bar:** A rounded rectangle (pill-shaped) with a Dark Grey background and a subtle magnifying glass icon. Text is left-aligned with "Light Grey" placeholder text.