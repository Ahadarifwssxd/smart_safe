/// A single admin-managed informational Panic Toolkit card. These are the
/// TEXT/GUIDANCE cards on the Panic Toolkit page (what to do, stay-calm steps,
/// after-the-incident advice) — NOT the interactive hardware tools (torch,
/// siren, fake call, distress timer) which stay wired in code.
///
/// One flexible shape covers every informational card so admins can edit them:
///  • title       → the card heading
///  • description  → a short line of context under the title
///  • steps        → an ordered/bulleted list of actions (empty for none)
///  • emoji        → optional leading emoji (used instead of [iconName] if set)
///  • iconName     → Material icon key, mapped via [iconFromName]
///  • colorHex     → accent colour for the icon/bullets
///  • category     → which section the card belongs to (see constants below)
class PanicTool {
  /// 'what_to_do' | 'stay_calm' | 'after'
  final String category;
  final String title;

  /// Short supporting line under the title.
  final String description;

  /// Bulleted action steps. Empty when the card is just a title + description.
  final List<String> steps;

  final String emoji;

  /// Material icon key — mapped via [iconFromName]. Used when [emoji] is empty.
  final String iconName;

  final int colorHex;
  final int sortOrder;

  const PanicTool({
    required this.category,
    this.title = '',
    this.description = '',
    this.steps = const [],
    this.emoji = '',
    this.iconName = '',
    this.colorHex = 0xFFE63946,
    this.sortOrder = 0,
  });

  factory PanicTool.fromMap(Map<String, dynamic> m) => PanicTool(
        category: m['category']?.toString() ?? kPanicWhatToDo,
        title: m['title']?.toString() ?? '',
        description: m['description']?.toString() ?? '',
        steps: (m['steps'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        emoji: m['emoji']?.toString() ?? '',
        iconName: m['iconName']?.toString() ?? '',
        colorHex: (m['colorHex'] as num?)?.toInt() ?? 0xFFE63946,
        sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

// Category keys (kept as constants to avoid typos across app + dashboard).
const String kPanicWhatToDo = 'what_to_do';
const String kPanicStayCalm = 'stay_calm';
const String kPanicAfter = 'after';

// Ordered list of categories with friendly labels for the admin CMS dropdown
// and the section headers on the page.
const Map<String, String> kPanicToolCategories = {
  kPanicWhatToDo: '🆘 What To Do Right Now',
  kPanicStayCalm: '🧘 Stay Calm & Breathe',
  kPanicAfter: '✅ After You\'re Safe',
};

// Icon keys usable for panic tool cards — all mapped in [iconFromName].
const List<String> kPanicToolIcons = [
  'shield_rounded',
  'campaign_rounded',
  'air_rounded',
  'healing_rounded',
  'location_on_rounded',
  'phone_forwarded_rounded',
  'warning_amber_rounded',
  'security_rounded',
  'lightbulb_rounded',
];

/// Built-in Panic Toolkit guidance seeded into Firestore on first run, and used
/// as the offline fallback when the collection is empty or offline before the
/// first sync — so the page is never blank. Admins can edit every item.
const List<PanicTool> defaultPanicTools = [
  // ─────────────────────── WHAT TO DO RIGHT NOW ───────────────────────
  PanicTool(
    category: kPanicWhatToDo,
    title: 'Get to a safe place',
    iconName: 'location_on_rounded',
    colorHex: 0xFFEF4444,
    sortOrder: 0,
    description:
        'Move toward people and light. Distance and witnesses are your best protection.',
    steps: [
      'Head to a shop, café, bank or any crowded place',
      'Walk on the main, well-lit road — avoid shortcuts and alleys',
      'If a vehicle is following, turn and walk the opposite way',
    ],
  ),
  PanicTool(
    category: kPanicWhatToDo,
    title: 'Attract attention',
    iconName: 'campaign_rounded',
    colorHex: 0xFFF59E0B,
    sortOrder: 1,
    description:
        'Noise scares off attackers and brings help fast. Use the Alarm Siren and Flashlight above.',
    steps: [
      'Shout "FIRE!" — people respond faster than to "help"',
      'Turn on the loud Alarm Siren and flash the torch',
      'Bang on doors, cars or shutters to draw a crowd',
    ],
  ),
  PanicTool(
    category: kPanicWhatToDo,
    title: 'Call for help',
    iconName: 'phone_forwarded_rounded',
    colorHex: 0xFF00B4D8,
    sortOrder: 2,
    description:
        'Reach someone who can act. Trigger SOS to alert all your contacts instantly.',
    steps: [
      'Press the SOS button to alert every emergency contact',
      'Call Police 15 or Rescue 1122',
      'Share your live location with a trusted person',
    ],
  ),

  // ─────────────────────── STAY CALM & BREATHE ───────────────────────
  PanicTool(
    category: kPanicStayCalm,
    title: 'Box breathing',
    iconName: 'air_rounded',
    colorHex: 0xFF06D6A0,
    sortOrder: 0,
    description:
        'Slow breathing lowers panic so you can think clearly and act.',
    steps: [
      'Breathe in through your nose for 4 seconds',
      'Hold your breath for 4 seconds',
      'Breathe out slowly for 4 seconds',
      'Repeat 4 times until your heart slows',
    ],
  ),
  PanicTool(
    category: kPanicStayCalm,
    title: 'Ground yourself',
    iconName: 'shield_rounded',
    colorHex: 0xFF9B5DE5,
    sortOrder: 1,
    description:
        'Anchoring your senses stops spiralling thoughts in a crisis.',
    steps: [
      'Name 5 things you can see',
      'Name 4 things you can touch',
      'Name 3 things you can hear',
      'Take one slow, deep breath',
    ],
  ),

  // ─────────────────────── AFTER YOU'RE SAFE ───────────────────────
  PanicTool(
    category: kPanicAfter,
    title: 'Tell someone you trust',
    iconName: 'healing_rounded',
    colorHex: 0xFF00B4D8,
    sortOrder: 0,
    description:
        'You do not have to handle this alone — reach out as soon as you are safe.',
    steps: [
      'Call a family member or close friend',
      'Tell them where you are and what happened',
      'Stay with people until you feel steady',
    ],
  ),
  PanicTool(
    category: kPanicAfter,
    title: 'Report the incident',
    iconName: 'warning_amber_rounded',
    colorHex: 0xFFEF4444,
    sortOrder: 1,
    description:
        'Reporting helps protect you and others from the same danger.',
    steps: [
      'Note the time, place and any details you remember',
      'Report to Police 15 or Madadgar 1099',
      'Do not clean up or change anything if evidence matters',
    ],
  ),
];
