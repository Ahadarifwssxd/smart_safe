import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DesignTokens {
  // Spacing (8pt Grid System + 4pt Grid Updates)
  static const double spaceXs  = 4.0;
  static const double spaceSm  = 8.0;
  static const double spaceMd  = 16.0;
  static const double spaceLg  = 24.0;
  static const double spaceXl  = 32.0;
  static const double space2xl = 48.0;

  // Legacy space constants (backward compatibility)
  static const double space2 = 2.0;
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space40 = 40.0;
  static const double space48 = 48.0;
  static const double space64 = 64.0;

  // Border Radii
  static const double radius4 = 4.0;
  static const double radius8 = 8.0;
  static const double radius12 = 12.0;
  static const double radius14 = 14.0; // Added for softer cards
  static const double radius16 = 16.0;
  static const double radius24 = 24.0;
  static const double radius32 = 32.0;
  
  static const BorderRadius borderRadius4 = BorderRadius.all(Radius.circular(radius4));
  static const BorderRadius borderRadius8 = BorderRadius.all(Radius.circular(radius8));
  static const BorderRadius borderRadius12 = BorderRadius.all(Radius.circular(radius12));
  static const BorderRadius borderRadius14 = BorderRadius.all(Radius.circular(radius14));
  static const BorderRadius borderRadius16 = BorderRadius.all(Radius.circular(radius16));
  static const BorderRadius borderRadius24 = BorderRadius.all(Radius.circular(radius24));
  static const BorderRadius borderRadius32 = BorderRadius.all(Radius.circular(radius32));

  // Animation Durations
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 250);
  static const Duration durationSlow = Duration(milliseconds: 400);

  // Typography Scale (Inter Font)
  // Memoized: these used to be getters that called GoogleFonts.inter(...) on
  // EVERY access — and they're read in build methods all over the app, so each
  // one was re-creating a TextStyle + re-running the font-family lookup
  // hundreds of times per frame batch. `static final` builds each once.
  static final TextStyle display = GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w800, // SOS button text level bold
        letterSpacing: -0.2, // Tighter negative letter spacing for large headers
      );

  static final TextStyle h1 = GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w700, // page headers
        letterSpacing: -0.2,
      );

  static final TextStyle h2 = GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w700, // large headers (20px+)
        letterSpacing: -0.2,
      );

  static final TextStyle h3 = GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      );

  static final TextStyle body = GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500, // Reduced from w600 to w500
      );

  static final TextStyle bodyStrong = GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w700, // genuinely stronger than `body` (w500)
      );

  static final TextStyle caption = GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
      );

  static final TextStyle label = GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w600, // uppercase labels font-weight 600
        letterSpacing: 1.2, // letter-spacing 1.2
      );
}
