// Generates the SmartSafe launcher icon: a bold RED tile, a white OUTLINED
// shield in the upper-middle, and rounded white "SOS" text below — a clean,
// high-recognition emergency mark.
//
// Renders at 3x (supersampled) then downscales for smooth anti-aliased edges,
// writes assets/icon/app_icon.png (1024) plus an optional 512 preview.
// Run:  dart run tool/generate_app_icon.dart [previewDir]

import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

const size = 1024;
const ss = 3;
const w = size * ss;

late img.Image image;

double _shieldHalf(double t, double hw) {
  if (t < 0 || t > 1) return 0;
  if (t < 0.08) {
    final k = t / 0.08;
    return hw * sqrt(max(0.0, 1 - (1 - k) * (1 - k)));
  }
  if (t < 0.52) return hw;
  final u = (t - 0.52) / 0.48;
  return hw * pow(1 - u, 0.8).toDouble();
}

void fillShield(double top, double sh, double hw, int r, int g, int b) {
  final cx = w / 2.0;
  for (var y = top.floor(); y <= (top + sh).ceil(); y++) {
    if (y < 0 || y >= w) continue;
    final t = (y - top) / sh;
    final hy = _shieldHalf(t, hw);
    if (hy <= 0) continue;
    for (var x = (cx - hy).floor(); x <= (cx + hy).ceil(); x++) {
      if (x < 0 || x >= w) continue;
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
}

void main(List<String> argv) {
  image = img.Image(width: w, height: w, numChannels: 4);

  // ── Background: solid emergency red with a very subtle top sheen ─────────
  const bgR = 0xEF, bgG = 0x44, bgB = 0x44;
  for (var y = 0; y < w; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgba(x, y, bgR, bgG, bgB, 255);
    }
  }
  // gentle radial highlight top-centre for a premium (not flat) feel
  final gcx = w * 0.5, gcy = w * 0.30, gr = w * 0.62;
  for (var y = 0; y < w; y++) {
    for (var x = 0; x < w; x++) {
      final dx = (x - gcx) / gr, dy = (y - gcy) / gr;
      final d = dx * dx + dy * dy;
      if (d < 1) {
        final a = (1 - d) * 0.10;
        final px = image.getPixel(x, y);
        image.setPixelRgba(
            x,
            y,
            (px.r + (255 - px.r) * a).round(),
            (px.g + (255 - px.g) * a).round(),
            (px.b + (255 - px.b) * a).round(),
            255);
      }
    }
  }

  // ── White OUTLINED shield (upper-middle) ────────────────────────────────
  final top = w * 0.235;
  final sh = w * 0.30;
  final hw = w * 0.145;
  final bw = hw * 0.20; // outer border thickness
  final gap = hw * 0.14; // gap between outer border and inner hairline
  final iw = hw * 0.08; // inner hairline thickness

  // 1) full white shield
  fillShield(top, sh, hw, 255, 255, 255);
  // 2) red inset -> leaves the thick white outer border
  fillShield(top + bw, sh - bw * 2.0, hw - bw, bgR, bgG, bgB);
  // 3) white inset -> start of thin inner hairline
  fillShield(top + bw + gap, sh - (bw + gap) * 2.0, hw - (bw + gap), 255, 255,
      255);
  // 4) red inset -> red interior, leaving only the thin inner hairline
  fillShield(top + bw + gap + iw, sh - (bw + gap + iw) * 2.0,
      hw - (bw + gap + iw), bgR, bgG, bgB);

  // ── Clean, premium white "SOS" below the shield ─────────────────────────
  // Bold rounded-capsule letters — solid and confident so the wordmark reads
  // as a strong, professional "SOS".
  const wr = 255, wg = 255, wb = 255;
  final cx = w / 2.0;
  final letH = w * 0.150; // letter height
  final letW = w * 0.108; // letter width
  final th = w * 0.037; // stroke thickness (bolder = more premium/confident)
  final hth = th / 2;
  final lgap = w * 0.030;
  final totalW = 3 * letW + 2 * lgap;
  final startX = cx - totalW / 2;
  final ly = w * 0.580;

  // Square corner/terminal fill — gives the letters FLAT, crisp terminals like
  // a clean grotesque sans (matching the app's "SOS" wordmark) instead of the
  // fully-rounded capsule look.
  void dot(double cxp, double cyp) {
    for (var y = (cyp - hth).floor(); y <= (cyp + hth).ceil(); y++) {
      if (y < 0 || y >= w) continue;
      for (var x = (cxp - hth).floor(); x <= (cxp + hth).ceil(); x++) {
        if (x < 0 || x >= w) continue;
        image.setPixelRgba(x, y, wr, wg, wb, 255);
      }
    }
  }

  void capH(double x1, double x2, double cyp) {
    for (var y = (cyp - hth).floor(); y <= (cyp + hth).ceil(); y++) {
      if (y < 0 || y >= w) continue;
      for (var x = x1.floor(); x <= x2.ceil(); x++) {
        if (x < 0 || x >= w) continue;
        image.setPixelRgba(x, y, wr, wg, wb, 255);
      }
    }
    dot(x1, cyp);
    dot(x2, cyp);
  }

  void capV(double cxp, double y1, double y2) {
    for (var y = y1.floor(); y <= y2.ceil(); y++) {
      if (y < 0 || y >= w) continue;
      for (var x = (cxp - hth).floor(); x <= (cxp + hth).ceil(); x++) {
        if (x < 0 || x >= w) continue;
        image.setPixelRgba(x, y, wr, wg, wb, 255);
      }
    }
    dot(cxp, y1);
    dot(cxp, y2);
  }

  // "S" — top bar, upper-left stem, middle bar, lower-right stem, bottom bar.
  void drawS(double lx) {
    final left = lx + hth, right = lx + letW - hth;
    capH(left, right, ly + hth);
    capV(left, ly + hth, ly + letH / 2);
    capH(left, right, ly + letH / 2);
    capV(right, ly + letH / 2, ly + letH - hth);
    capH(left, right, ly + letH - hth);
  }

  void drawO(double lx) {
    final ox = lx + letW / 2, oy = ly + letH / 2;
    final rxO = letW / 2, ryO = letH / 2;
    final rxI = rxO - th, ryI = ryO - th;
    for (var y = ly.floor(); y <= (ly + letH).ceil(); y++) {
      if (y < 0 || y >= w) continue;
      for (var x = lx.floor(); x <= (lx + letW).ceil(); x++) {
        if (x < 0 || x >= w) continue;
        final nxO = (x - ox) / rxO, nyO = (y - oy) / ryO;
        final nxI = (x - ox) / rxI, nyI = (y - oy) / ryI;
        if (nxO * nxO + nyO * nyO <= 1 && nxI * nxI + nyI * nyI > 1) {
          image.setPixelRgba(x, y, wr, wg, wb, 255);
        }
      }
    }
  }

  drawS(startX);
  drawO(startX + letW + lgap);
  drawS(startX + 2 * (letW + lgap));

  final out = img.copyResize(image,
      width: size, height: size, interpolation: img.Interpolation.cubic);

  final dir = Directory('assets/icon');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('assets/icon/app_icon.png').writeAsBytesSync(img.encodePng(out));
  stdout.writeln('Wrote assets/icon/app_icon.png (${size}x$size)');

  if (argv.isNotEmpty) {
    final prev = img.copyResize(image,
        width: 512, height: 512, interpolation: img.Interpolation.cubic);
    final p = '${argv[0]}/app_icon_preview.png';
    File(p).writeAsBytesSync(img.encodePng(prev));
    stdout.writeln('Wrote preview $p');
  }
}
