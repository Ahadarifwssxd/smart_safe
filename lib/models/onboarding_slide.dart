/// A single admin-managed onboarding slide shown on the app's first-run
/// Onboarding walkthrough. Each slide is a full-screen intro card:
///  • emoji      → the big glyph inside the circle
///  • title      → the bold headline
///  • subtitle   → the supporting paragraph under the title
///  • colorHex   → accent colour for the circle/border
///  • sortOrder  → position in the walkthrough (ascending)
class OnboardingSlide {
  final String emoji;
  final String title;
  final String subtitle;
  final int colorHex;
  final int sortOrder;

  const OnboardingSlide({
    this.emoji = '',
    this.title = '',
    this.subtitle = '',
    this.colorHex = 0xFFEF4444,
    this.sortOrder = 0,
  });

  factory OnboardingSlide.fromMap(Map<String, dynamic> m) => OnboardingSlide(
        emoji: m['emoji']?.toString() ?? '',
        title: m['title']?.toString() ?? '',
        subtitle: m['subtitle']?.toString() ?? '',
        colorHex: (m['colorHex'] as num?)?.toInt() ?? 0xFFEF4444,
        sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

/// Built-in onboarding slides seeded into Firestore on first run, and used as
/// the offline fallback when the collection is empty or offline before the
/// first sync — so the walkthrough is never blank. Admins can edit every slide.
const List<OnboardingSlide> defaultOnboardingSlides = [
  OnboardingSlide(
    emoji: '🆘',
    title: 'One tap saves lives',
    subtitle:
        'SmartSafe sends your GPS location to 4 trusted contacts + calls 1122 ambulance in under 10 seconds.',
    colorHex: 0xFFEF4444,
    sortOrder: 0,
  ),
  OnboardingSlide(
    emoji: '📍',
    title: 'Always know you\'re tracked',
    subtitle:
        'Live GPS sharing, crash detection, and safe route planner work together to keep you protected 24/7.',
    colorHex: 0xFFEF4444,
    sortOrder: 1,
  ),
  OnboardingSlide(
    emoji: '👥',
    title: 'Your circle protects you',
    subtitle:
        'Add up to 5 trusted contacts. They get instant SMS + app alerts whenever you need help.',
    colorHex: 0xFFEF4444,
    sortOrder: 2,
  ),
  OnboardingSlide(
    emoji: '🛡️',
    title: 'Silent. Powerful. Yours.',
    subtitle:
        'Shake your phone 3 times to trigger a silent SOS. No sound, no screen flash. Nobody notices.',
    colorHex: 0xFF22C55E,
    sortOrder: 3,
  ),
];
