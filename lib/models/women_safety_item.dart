/// A single admin-managed Women Safety resource. One flexible shape covers all
/// six sections of the Women Safety page so admins can edit every item:
///  • warning    → title + [items] (warning signs) + subtitle (the "DO:" action) + colorHex
///  • prevention → iconName + title + subtitle (tip) + colorHex
///  • defense    → title (emoji-label move) + subtitle (detail)
///  • carry      → emoji + title (item) + subtitle (short detail)
///  • worst      → title (step number) + subtitle (step text)
///  • helpline   → emoji + title (name) + number (tap-to-call)
class WomenSafetyItem {
  /// 'warning' | 'prevention' | 'defense' | 'carry' | 'worst' | 'helpline'
  final String category;
  final String title;

  /// Holds the tip / detail / action / step-text depending on category.
  final String subtitle;

  /// Warning signs list (bullet points). Empty for other categories.
  final List<String> items;

  final String emoji;

  /// Material icon key for prevention tips — mapped via [iconFromName].
  final String iconName;

  /// Helpline phone number (helpline category only).
  final String number;

  final int colorHex;
  final int sortOrder;

  const WomenSafetyItem({
    required this.category,
    this.title = '',
    this.subtitle = '',
    this.items = const [],
    this.emoji = '',
    this.iconName = '',
    this.number = '',
    this.colorHex = 0xFFEF4444,
    this.sortOrder = 0,
  });

  factory WomenSafetyItem.fromMap(Map<String, dynamic> m) => WomenSafetyItem(
        category: m['category']?.toString() ?? kWsWarning,
        title: m['title']?.toString() ?? '',
        subtitle: m['subtitle']?.toString() ?? '',
        items: (m['items'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        emoji: m['emoji']?.toString() ?? '',
        iconName: m['iconName']?.toString() ?? '',
        number: m['number']?.toString() ?? '',
        colorHex: (m['colorHex'] as num?)?.toInt() ?? 0xFFEF4444,
        sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

// Category keys (kept as constants to avoid typos across app + dashboard).
const String kWsWarning = 'warning';
const String kWsPrevention = 'prevention';
const String kWsDefense = 'defense';
const String kWsCarry = 'carry';
const String kWsWorst = 'worst';
const String kWsHelpline = 'helpline';

// Ordered list of categories with friendly labels for the admin CMS dropdown.
const Map<String, String> kWomenSafetyCategories = {
  kWsWarning: '⚠️ Warning Sign',
  kWsPrevention: '🛡️ Prevention Tip',
  kWsDefense: '🥊 Self-Defense Move',
  kWsCarry: '🎒 What to Carry',
  kWsWorst: '🚨 If Worst Happens',
  kWsHelpline: '📞 Quick Helpline',
};

// Icon keys usable for prevention tips — all mapped in [iconFromName].
const List<String> kWomenSafetyIcons = [
  'share_location_rounded',
  'headphones_rounded',
  'light_mode_rounded',
  'local_taxi_rounded',
  'phone_in_talk_rounded',
];

/// Built-in Women Safety content seeded into Firestore on first run, and used as
/// the offline fallback when the collection is empty or offline before the first
/// sync — so the page is never blank. Faithfully extracted from the original
/// static page so nothing is lost and admins can edit every item.
const List<WomenSafetyItem> defaultWomenSafetyItems = [
  // ─────────────────────── WARNING SIGNS ───────────────────────
  WomenSafetyItem(
    category: kWsWarning,
    title: 'Someone following you',
    colorHex: 0xFFEF4444,
    sortOrder: 0,
    items: [
      'Same person behind you for 3+ blocks',
      'Person changes direction when you do',
      'Slows down or speeds up to match your pace',
      'Makes eye contact repeatedly',
    ],
    subtitle:
        'DO: Cross the street, enter a shop, call someone loudly, trigger SOS if needed',
  ),
  WomenSafetyItem(
    category: kWsWarning,
    title: 'Uncomfortable conversation',
    colorHex: 0xFFF59E0B,
    sortOrder: 1,
    items: [
      'Stranger asks too many personal questions',
      'Won\'t leave when you ask politely',
      'Tries to isolate you from others',
      'Offers unsolicited help or rides',
    ],
    subtitle:
        'DO: Say "NO" firmly and loudly, move toward people, don\'t explain yourself',
  ),
  WomenSafetyItem(
    category: kWsWarning,
    title: 'Dangerous situation escalating',
    colorHex: 0xFFEF4444,
    sortOrder: 2,
    items: [
      'Person blocks your way',
      'Grabs your arm or tries to touch',
      'Threatens you verbally',
      'You feel trapped or cornered',
    ],
    subtitle:
        'DO: Scream "FIRE!" (people respond faster), run to lit areas, trigger Silent SOS NOW',
  ),

  // ─────────────────────── PREVENTION TIPS ───────────────────────
  WomenSafetyItem(
    category: kWsPrevention,
    iconName: 'share_location_rounded',
    title: 'Share your route',
    colorHex: 0xFFEF4444,
    sortOrder: 0,
    subtitle:
        'Send your destination + route to 2 people. Use SmartSafe\'s Safe Route feature before traveling at night.',
  ),
  WomenSafetyItem(
    category: kWsPrevention,
    iconName: 'headphones_rounded',
    title: 'Stay aware — no headphones',
    colorHex: 0xFFF59E0B,
    sortOrder: 1,
    subtitle:
        'Keep one ear free or no music at all. Attackers target distracted people.',
  ),
  WomenSafetyItem(
    category: kWsPrevention,
    iconName: 'light_mode_rounded',
    title: 'Stick to well-lit areas',
    colorHex: 0xFF22C55E,
    sortOrder: 2,
    subtitle:
        'Avoid shortcuts through dark alleys. Walk on main roads even if it takes 5 minutes longer.',
  ),
  WomenSafetyItem(
    category: kWsPrevention,
    iconName: 'local_taxi_rounded',
    title: 'Use verified transport',
    colorHex: 0xFFEF4444,
    sortOrder: 3,
    subtitle:
        'Book Careem/Uber, not random taxis. Share ride details + driver photo with family.',
  ),
  WomenSafetyItem(
    category: kWsPrevention,
    iconName: 'phone_in_talk_rounded',
    title: 'Fake phone call trick',
    colorHex: 0xFFEF4444,
    sortOrder: 4,
    subtitle:
        'Pretend to talk loudly: "I will arrive in five minutes. Please wait outside." This can make you seem expected.',
  ),

  // ─────────────────────── SELF-DEFENSE MOVES ───────────────────────
  WomenSafetyItem(
    category: kWsDefense,
    title: '👁️ Eyes',
    sortOrder: 0,
    subtitle: 'Jab fingers toward eyes — instant pain, they can\'t see',
  ),
  WomenSafetyItem(
    category: kWsDefense,
    title: '👃 Nose',
    sortOrder: 1,
    subtitle: 'Palm strike upward on nose — extremely painful, bleeding',
  ),
  WomenSafetyItem(
    category: kWsDefense,
    title: '🗣️ Throat',
    sortOrder: 2,
    subtitle: 'Karate chop to throat — hard to breathe, immediate stop',
  ),
  WomenSafetyItem(
    category: kWsDefense,
    title: '🦵 Groin',
    sortOrder: 3,
    subtitle: 'Knee kick or hard stomp — works on any male attacker',
  ),
  WomenSafetyItem(
    category: kWsDefense,
    title: '🦶 Stomp',
    sortOrder: 4,
    subtitle: 'Heel stomp on foot — if grabbed from behind, crush their toes',
  ),

  // ─────────────────────── WHAT TO CARRY ───────────────────────
  WomenSafetyItem(
    category: kWsCarry,
    emoji: '📱',
    title: 'Charged phone',
    sortOrder: 0,
    subtitle: '60%+ battery',
  ),
  WomenSafetyItem(
    category: kWsCarry,
    emoji: '🔑',
    title: 'Keys ready',
    sortOrder: 1,
    subtitle: 'Held in fist',
  ),
  WomenSafetyItem(
    category: kWsCarry,
    emoji: '💡',
    title: 'Flashlight',
    sortOrder: 2,
    subtitle: 'Phone torch',
  ),
  WomenSafetyItem(
    category: kWsCarry,
    emoji: '👟',
    title: 'Flat shoes',
    sortOrder: 3,
    subtitle: 'Run easily',
  ),

  // ─────────────────────── IF WORST HAPPENS ───────────────────────
  WomenSafetyItem(
    category: kWsWorst,
    title: '1',
    sortOrder: 0,
    subtitle: 'Get to safety first — find people, lit area, shop, hospital',
  ),
  WomenSafetyItem(
    category: kWsWorst,
    title: '2',
    sortOrder: 1,
    subtitle: 'Call trusted person — family member or close friend',
  ),
  WomenSafetyItem(
    category: kWsWorst,
    title: '3',
    sortOrder: 2,
    subtitle:
        'DO NOT wash, change clothes, or clean yourself — evidence is critical',
  ),
  WomenSafetyItem(
    category: kWsWorst,
    title: '4',
    sortOrder: 3,
    subtitle: 'Call Madadgar 1099 or Police 15 to report',
  ),
  WomenSafetyItem(
    category: kWsWorst,
    title: '5',
    sortOrder: 4,
    subtitle:
        'Go to nearest hospital for medical exam (medico-legal report)',
  ),

  // ─────────────────────── QUICK HELPLINES ───────────────────────
  WomenSafetyItem(
    category: kWsHelpline,
    emoji: '🚓',
    title: 'Police',
    number: '15',
    sortOrder: 0,
  ),
  WomenSafetyItem(
    category: kWsHelpline,
    emoji: '🚑',
    title: 'Rescue',
    number: '1122',
    sortOrder: 1,
  ),
  WomenSafetyItem(
    category: kWsHelpline,
    emoji: '🆘',
    title: 'Madadgar',
    number: '1099',
    sortOrder: 2,
  ),
  WomenSafetyItem(
    category: kWsHelpline,
    emoji: '☎️',
    title: 'Aurat Fdn',
    number: '0421110028 82',
    sortOrder: 3,
  ),
];
