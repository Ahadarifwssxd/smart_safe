// Generates 3 candidate SmartSafe launcher icons for the user to pick from.
// Outputs 512px previews to the scratchpad. Run:
//   dart run tool/generate_icon_candidates.dart <outDir>

import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

const size = 1024;
const ss = 3;
const w = size * ss;

void fillGradient(
    img.Image im, int tr, int tg, int tb, int br, int bg, int bb) {
  for (var y = 0; y < w; y++) {
    final t = y / (w - 1);
    final r = (tr + (br - tr) * t).round();
    final g = (tg + (bg - tg) * t).round();
    final b = (tb + (bb - tb) * t).round();
    for (var x = 0; x < w; x++) {
      im.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  // Soft radial glow top-centre for depth.
  final gcx = w * 0.5, gcy = w * 0.30, gr = w * 0.55;
  for (var y = 0; y < w; y++) {
    for (var x = 0; x < w; x++) {
      final dx = (x - gcx) / gr, dy = (y - gcy) / gr;
      final d = dx * dx + dy * dy;
      if (d < 1) {
        final a = (1 - d) * 0.16;
        final px = im.getPixel(x, y);
        im.setPixelRgba(
            x,
            y,
            (px.r + (255 - px.r) * a).round(),
            (px.g + (255 - px.g) * a).round(),
            (px.b + (255 - px.b) * a).round(),
            255);
      }
    }
  }
}

double shieldHalf(double t, double hw) {
  if (t < 0 || t > 1) return 0;
  if (t < 0.07) {
    final k = t / 0.07;
    return hw * sqrt(max(0.0, 1 - (1 - k) * (1 - k)));
  }
  if (t < 0.5) return hw;
  final u = (t - 0.5) / 0.5;
  return hw * pow(1 - u, 0.85).toDouble();
}

void drawShield(img.Image im, double cx, double top, double sh, double hw) {
  // Soft drop shadow.
  for (var y = 0; y < w; y++) {
    final t = (y - top - w * 0.012) / sh;
    if (t < 0 || t > 1) continue;
    final hy = shieldHalf(t, hw) + w * 0.006;
    for (var x = (cx - hy).floor(); x <= (cx + hy).ceil(); x++) {
      if (x < 0 || x >= w) continue;
      im.setPixelRgba(x, y, 40, 30, 95, 255);
    }
  }
  // White shield with a gentle sheen.
  for (var y = 0; y < w; y++) {
    final t = (y - top) / sh;
    if (t < 0 || t > 1) continue;
    final hy = shieldHalf(t, hw);
    final r = (255 - 30 * t).round().clamp(220, 255);
    final g = (255 - 26 * t).round().clamp(224, 255);
    final b = (255 - 16 * t).round().clamp(234, 255);
    for (var x = (cx - hy).floor(); x <= (cx + hy).ceil(); x++) {
      if (x < 0 || x >= w) continue;
      im.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  // Glossy highlight (upper-left).
  final glCx = cx - hw * 0.28, glCy = top + sh * 0.15;
  final glRx = hw * 1.0, glRy = sh * 0.30;
  for (var y = top.floor(); y < (top + sh * 0.58).ceil(); y++) {
    if (y < 0 || y >= w) continue;
    final t = (y - top) / sh;
    final hy = shieldHalf(t, hw);
    for (var x = (cx - hy).floor(); x <= (cx + hy).ceil(); x++) {
      if (x < 0 || x >= w) continue;
      final nx = (x - glCx) / glRx, ny = (y - glCy) / glRy;
      final d = nx * nx + ny * ny;
      if (d < 1) {
        final a = (1 - d) * 0.4;
        final px = im.getPixel(x, y);
        im.setPixelRgba(
            x,
            y,
            (px.r + (255 - px.r) * a).round(),
            (px.g + (255 - px.g) * a).round(),
            (px.b + (255 - px.b) * a).round(),
            255);
      }
    }
  }
}

bool inHeart(double x, double y) {
  final a = x * x + y * y - 1;
  return a * a * a - x * x * y * y * y <= 0;
}

void drawHeart(
    img.Image im, double cx, double cy, double r, int cr, int cg, int cb) {
  for (var y = (cy - r * 1.5).floor(); y <= (cy + r * 1.6).ceil(); y++) {
    if (y < 0 || y >= w) continue;
    for (var x = (cx - r * 1.5).floor(); x <= (cx + r * 1.5).ceil(); x++) {
      if (x < 0 || x >= w) continue;
      final nx = (x - cx) / r;
      final ny = -(y - cy) / r;
      if (inHeart(nx, ny)) im.setPixelRgba(x, y, cr, cg, cb, 255);
    }
  }
}

void disc(img.Image im, double cx, double cy, double rad, int r, int g, int b) {
  for (var y = (cy - rad).floor(); y <= (cy + rad).ceil(); y++) {
    if (y < 0 || y >= w) continue;
    for (var x = (cx - rad).floor(); x <= (cx + rad).ceil(); x++) {
      if (x < 0 || x >= w) continue;
      final dx = x - cx, dy = y - cy;
      if (dx * dx + dy * dy <= rad * rad) im.setPixelRgba(x, y, r, g, b, 255);
    }
  }
}

void thickLine(img.Image im, double x1, double y1, double x2, double y2,
    double rad, int r, int g, int b) {
  final dist = sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
  final steps = dist.ceil();
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    disc(im, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, rad, r, g, b);
  }
}

// Draws an ECG/heartbeat polyline centred at (cx,cy), spanning halfW each side.
void drawPulse(img.Image im, double cx, double cy, double halfW, double amp,
    double rad, int r, int g, int b) {
  // Normalised x, y offsets (y positive = up).
  const pts = <List<double>>[
    [-1.0, 0.0],
    [-0.45, 0.0],
    [-0.28, 0.55],
    [-0.12, -0.75],
    [0.05, 0.95],
    [0.22, -0.55],
    [0.38, 0.0],
    [1.0, 0.0],
  ];
  for (var i = 0; i < pts.length - 1; i++) {
    final ax = cx + pts[i][0] * halfW;
    final ay = cy - pts[i][1] * amp;
    final bx = cx + pts[i + 1][0] * halfW;
    final by = cy - pts[i + 1][1] * amp;
    thickLine(im, ax, ay, bx, by, rad, r, g, b);
  }
}

img.Image _newTile() => img.Image(width: w, height: w, numChannels: 4);

void _save(img.Image im, String path) {
  final out = img.copyResize(im,
      width: 512, height: 512, interpolation: img.Interpolation.cubic);
  File(path).writeAsBytesSync(img.encodePng(out));
  stdout.writeln('wrote $path');
}

void main(List<String> argv) {
  final outDir = argv.isNotEmpty ? argv[0] : '.';
  Directory(outDir).createSync(recursive: true);

  const topR = 0x6D, topG = 0x75, topB = 0xF5;
  const botR = 0x43, botG = 0x38, botB = 0xCA;
  const red = [0xE0, 0x24, 0x2E];

  final cx = w / 2.0;
  final top = w * 0.185;
  final sh = w * 0.63;
  final hw = w * 0.255;

  // ── A: Shield + red heart + white pulse ─────────────────────────────
  {
    final im = _newTile();
    fillGradient(im, topR, topG, topB, botR, botG, botB);
    drawShield(im, cx, top, sh, hw);
    final hcy = top + sh * 0.36;
    drawHeart(im, cx, hcy, w * 0.115, red[0], red[1], red[2]);
    drawPulse(im, cx, hcy + w * 0.006, w * 0.10, w * 0.05, w * 0.011, 255, 255,
        255);
    _save(im, '$outDir/candidateA.png');
  }

  // ── B: Shield + bold red heartbeat line ─────────────────────────────
  {
    final im = _newTile();
    fillGradient(im, topR, topG, topB, botR, botG, botB);
    drawShield(im, cx, top, sh, hw);
    final ccy = top + sh * 0.40;
    drawPulse(im, cx, ccy, w * 0.165, w * 0.11, w * 0.02, red[0], red[1],
        red[2]);
    _save(im, '$outDir/candidateB.png');
  }

  // ── C: Big white heart + red pulse (no shield) ──────────────────────
  {
    final im = _newTile();
    fillGradient(im, topR, topG, topB, botR, botG, botB);
    // subtle shadow behind heart
    drawHeart(im, cx + w * 0.008, w * 0.47 + w * 0.01, w * 0.235, 40, 30, 95);
    drawHeart(im, cx, w * 0.47, w * 0.23, 255, 255, 255);
    drawPulse(im, cx, w * 0.47 + w * 0.01, w * 0.155, w * 0.075, w * 0.019,
        red[0], red[1], red[2]);
    _save(im, '$outDir/candidateC.png');
  }

  stdout.writeln('DONE');
}
