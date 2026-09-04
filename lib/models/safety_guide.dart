/// A single admin-managed safety guide shown on the Driving / Child Safety /
/// First-Aid pages. One flexible shape covers all three:
///  • first_aid → emoji + title + urgent flag + ordered [steps]
///  • driving   → title + [steps] (checklist / rules) + optional [detail]
///  • child     → emoji + title + lesson text in [detail] and/or [steps]
class SafetyGuide {
  /// 'driving' | 'child' | 'first_aid'
  final String category;
  final String title;
  final String emoji;

  /// Optional one-line description shown under the title.
  final String detail;

  /// Ordered steps / checklist items / bullet points.
  final List<String> steps;

  final int colorHex;

  /// First-aid urgency badge (also usable to highlight critical guides).
  final bool urgent;

  final int sortOrder;

  const SafetyGuide({
    required this.category,
    required this.title,
    this.emoji = '📌',
    this.detail = '',
    this.steps = const [],
    this.colorHex = 0xFF00B4D8,
    this.urgent = false,
    this.sortOrder = 0,
  });

  factory SafetyGuide.fromMap(Map<String, dynamic> m) => SafetyGuide(
        category: m['category']?.toString() ?? 'first_aid',
        title: m['title']?.toString() ?? '',
        emoji: m['emoji']?.toString() ?? '📌',
        detail: m['detail']?.toString() ?? '',
        steps: (m['steps'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        colorHex: (m['colorHex'] as num?)?.toInt() ?? 0xFF00B4D8,
        urgent: m['urgent'] == true,
        sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

// Category keys (kept as constants to avoid typos across app + dashboard).
const String kGuideDriving = 'driving';
const String kGuideChild = 'child';
const String kGuideFirstAid = 'first_aid';

/// Built-in content seeded into Firestore on first run, and used as the offline
/// fallback when Firestore has no guides yet. Extracted from the original
/// static pages so nothing is lost and admins can edit every item.
const List<SafetyGuide> defaultSafetyGuides = [
  // ─────────────────────── FIRST AID ───────────────────────
  SafetyGuide(
    category: kGuideFirstAid,
    emoji: '❤️',
    title: 'CPR — Heart not beating',
    urgent: true,
    colorHex: 0xFFE63946,
    sortOrder: 0,
    steps: [
      'Call 1122 FIRST — tell them location',
      'Lay person flat on hard surface',
      'Tilt head back, lift chin to open airway',
      'Place heel of hand on center of chest',
      'Push DOWN hard — 5-6 cm deep',
      '30 compressions then 2 rescue breaths',
      'Speed: 100-120 compressions per minute',
      'Continue until ambulance arrives',
    ],
  ),
  SafetyGuide(
    category: kGuideFirstAid,
    emoji: '🩸',
    title: 'Heavy bleeding',
    urgent: true,
    colorHex: 0xFFE63946,
    sortOrder: 1,
    steps: [
      'Put on gloves if available',
      'Press HARD on wound with clean cloth',
      'Do NOT remove cloth — add more on top',
      'Raise injured limb above heart level',
      'Tie cloth firmly — not too tight',
      'Call 1122 immediately',
      'Keep person lying down, legs raised',
      'Talk to them — keep them conscious',
    ],
  ),
  SafetyGuide(
    category: kGuideFirstAid,
    emoji: '🔥',
    title: 'Burns',
    colorHex: 0xFFF4A261,
    sortOrder: 2,
    steps: [
      'Remove from heat source FIRST',
      'Cool burn under COLD running water — 20 min',
      'DO NOT use ice, butter, or toothpaste',
      'Remove rings/jewelry before swelling',
      'Cover loosely with clean cloth',
      'DO NOT pop blisters',
      'For face/hands/large burns — go to ER',
      'Give paracetamol for pain',
    ],
  ),
  SafetyGuide(
    category: kGuideFirstAid,
    emoji: '😮',
    title: 'Choking — adult',
    urgent: true,
    colorHex: 0xFFF4A261,
    sortOrder: 3,
    steps: [
      'Ask "Are you choking?" — if yes, act fast',
      'Give 5 firm back blows between shoulder blades',
      'Stand behind person, arms around waist',
      'Make fist above belly button, below chest',
      'Pull SHARPLY inward and upward 5 times',
      'Repeat back blows + abdominal thrusts',
      'If unconscious — start CPR',
      'Call 1122 if object not removed in 1 min',
    ],
  ),
  SafetyGuide(
    category: kGuideFirstAid,
    emoji: '🤕',
    title: 'Head injury / concussion',
    urgent: true,
    colorHex: 0xFFE63946,
    sortOrder: 4,
    steps: [
      'Call 1122 if person is unconscious',
      'Keep them still — do NOT move neck',
      'Check breathing and pulse',
      'If vomiting — gently roll to side',
      'Apply ice pack for swelling (not direct skin)',
      'Watch for: confusion, unequal pupils, seizure',
      'Do NOT give aspirin (increases bleeding)',
      'Go to ER even if person seems fine',
    ],
  ),
  SafetyGuide(
    category: kGuideFirstAid,
    emoji: '🦴',
    title: 'Broken bone / fracture',
    colorHex: 0xFFE63946,
    sortOrder: 5,
    steps: [
      'Do NOT try to straighten the bone',
      'Immobilize — splint with cardboard/wood',
      'Pad the splint with cloth for comfort',
      'Tie splint above AND below fracture',
      'Elevate if possible to reduce swelling',
      'Apply ice pack wrapped in cloth',
      'Check pulse below fracture every 10 min',
      'Go to hospital — X-ray needed',
    ],
  ),
  SafetyGuide(
    category: kGuideFirstAid,
    emoji: '⚡',
    title: 'Electric shock',
    urgent: true,
    colorHex: 0xFFF4A261,
    sortOrder: 6,
    steps: [
      'DO NOT touch person while still in contact',
      'Turn off electricity at main switch',
      'Use DRY wood/plastic to push wire away',
      'Call 1122 immediately',
      'Check breathing — start CPR if needed',
      'Even if seems OK — internal burns possible',
      'Keep warm with blanket',
      'Do NOT give food or water',
    ],
  ),
  SafetyGuide(
    category: kGuideFirstAid,
    emoji: '🌡️',
    title: 'Heat stroke',
    urgent: true,
    colorHex: 0xFFE63946,
    sortOrder: 7,
    steps: [
      'Move to cool/shaded area immediately',
      'Call 1122 — heat stroke is life-threatening',
      'Remove excess clothing',
      'Cool with cold wet cloths on neck, armpits, groin',
      'Fan the person continuously',
      'Give water ONLY if conscious and can swallow',
      'DO NOT give aspirin or paracetamol',
      'Place in recovery position if unconscious',
    ],
  ),

  // ─────────────────────── DRIVING ───────────────────────
  SafetyGuide(
    category: kGuideDriving,
    emoji: '🚗',
    title: 'Vehicle check (2 minutes)',
    detail: 'Quick pre-drive checklist before you start',
    colorHex: 0xFFE63946,
    sortOrder: 0,
    steps: [
      'Fuel gauge — at least 1/4 tank',
      'Tire pressure — check all 4 tires',
      'Mirrors — adjust all 3 (rear + side)',
      'Lights — headlights, indicators, brake lights working',
      'Seatbelt — everyone buckled up',
    ],
  ),
  SafetyGuide(
    category: kGuideDriving,
    emoji: '📱',
    title: 'Phone discipline while driving',
    detail: 'Stay focused and stay reachable',
    colorHex: 0xFFE63946,
    sortOrder: 1,
    steps: [
      'Phone on silent or DND — one glance = 5 seconds blind. At 60km/h you travel 83 meters blind.',
      'Keep phone charged 60%+ so crash detection stays ON and emergency calls work.',
    ],
  ),
  SafetyGuide(
    category: kGuideDriving,
    emoji: '🛡️',
    title: 'Defensive driving rules',
    detail: 'Habits that prevent most accidents',
    colorHex: 0xFFE63946,
    sortOrder: 2,
    steps: [
      '3-second rule: keep 3 seconds from the car ahead. Pick a landmark and count "1, 2, 3". If you pass it before 3, you\'re TOO CLOSE.',
      'Check mirrors every 5-8 seconds: rear then left then right. Always know what\'s behind and beside you.',
      'Hands at 9 & 3 position (not 10 & 2) — airbags deploy safely and prevent arm injuries.',
      'Scan 12-15 seconds ahead for brake lights, obstacles and lane changes — not just the car in front.',
    ],
  ),
  SafetyGuide(
    category: kGuideDriving,
    emoji: '🏍️',
    title: 'Motorcycle suddenly cuts in front',
    detail: 'Motorcycles weave through traffic and hide in blind spots',
    colorHex: 0xFFE63946,
    sortOrder: 3,
    steps: [
      'Always check blind spot before lane change',
      'Use indicators 3 seconds before turning',
      'Expect motorcycles to appear from nowhere',
    ],
  ),
  SafetyGuide(
    category: kGuideDriving,
    emoji: '🚶',
    title: 'Pedestrian crosses without warning',
    detail: 'People step onto the road without looking, especially near bus stops',
    colorHex: 0xFFF4A261,
    sortOrder: 4,
    steps: [
      'Slow down near bus stops and markets',
      'Hover foot over brake in crowded areas',
      'Make eye contact with pedestrians',
    ],
  ),
  SafetyGuide(
    category: kGuideDriving,
    emoji: '🛑',
    title: 'Car brakes suddenly in front',
    detail: 'The driver ahead may be distracted or braked late',
    colorHex: 0xFFE63946,
    sortOrder: 5,
    steps: [
      'Keep 3-second following distance',
      'Watch brake lights 2-3 cars ahead',
      'Don\'t tailgate — ever',
    ],
  ),
  SafetyGuide(
    category: kGuideDriving,
    emoji: '🌧️',
    title: 'Bad weather driving',
    detail: 'Adjust for rain, fog, glare and night',
    colorHex: 0xFFE63946,
    sortOrder: 6,
    steps: [
      'Rain: reduce speed 20% and double your following distance.',
      'Fog: fog lights ON and go slow.',
      'Sun glare: sunglasses on and visor down.',
      'Night: high beam only if there is no oncoming traffic.',
    ],
  ),
  SafetyGuide(
    category: kGuideDriving,
    emoji: '🛞',
    title: 'Tire blowout',
    urgent: true,
    colorHex: 0xFFE63946,
    sortOrder: 7,
    steps: [
      'DON\'T brake hard — car will spin',
      'Hold steering wheel TIGHT',
      'Let car slow down naturally',
      'Pull to side slowly',
    ],
  ),
  SafetyGuide(
    category: kGuideDriving,
    emoji: '🚨',
    title: 'Brake failure',
    urgent: true,
    colorHex: 0xFFE63946,
    sortOrder: 8,
    steps: [
      'Pump brakes rapidly',
      'Shift to lower gear',
      'Use handbrake SLOWLY',
      'Aim for soft obstacles (bushes) not walls',
    ],
  ),
  SafetyGuide(
    category: kGuideDriving,
    emoji: '💥',
    title: 'If an accident happens',
    urgent: true,
    colorHex: 0xFFE63946,
    sortOrder: 9,
    steps: [
      'Turn on hazard lights immediately',
      'Move car to roadside if possible',
      'Place warning triangle 30m behind',
      'SmartSafe auto-calls 1122 + contacts',
    ],
  ),
  SafetyGuide(
    category: kGuideDriving,
    emoji: '🇵🇰',
    title: 'Pakistan road challenges',
    detail: 'Local hazards and how to handle them',
    colorHex: 0xFF06D6A0,
    sortOrder: 10,
    steps: [
      'Unmarked speed breakers: slow down near schools, hospitals and housing societies; watch for tire marks.',
      'Donkey carts and rickshaws: give wide berth — they stop or turn without warning. Never honk aggressively.',
      'Encroachments on road: markets spill onto roads. Drive in the leftmost lane and expect pedestrians.',
      'Motorcycles without lights at night: use high beam on empty roads and flash before overtaking.',
    ],
  ),

  // ─────────────────────── CHILD ───────────────────────
  SafetyGuide(
    category: kGuideChild,
    emoji: '🚫',
    title: 'Never go with a stranger',
    detail: 'Teach: "No matter what reason they give — lost dog, your mom sent me — NEVER go with a stranger."',
    colorHex: 0xFFE63946,
    sortOrder: 0,
  ),
  SafetyGuide(
    category: kGuideChild,
    emoji: '📢',
    title: 'Scream and run',
    detail: 'Teach: "If someone grabs you, scream HELP! as loud as you can and run to a crowded place."',
    colorHex: 0xFFF4A261,
    sortOrder: 1,
  ),
  SafetyGuide(
    category: kGuideChild,
    emoji: '🤝',
    title: 'Safe adults to trust',
    detail: 'Teach: "If you\'re in trouble — go to a policeman, shopkeeper, teacher, or any woman with children."',
    colorHex: 0xFFE63946,
    sortOrder: 2,
  ),
  SafetyGuide(
    category: kGuideChild,
    emoji: '📱',
    title: 'Remember important numbers',
    detail: 'Child should memorize: parent\'s number, home number, and know to call 15 (police) in emergency.',
    colorHex: 0xFFE63946,
    sortOrder: 3,
  ),
  SafetyGuide(
    category: kGuideChild,
    emoji: '🙅',
    title: 'Body autonomy',
    detail: 'Teach: "No one should touch your private parts. If someone does, it\'s NOT your fault. Tell mama/baba immediately."',
    colorHex: 0xFFE63946,
    sortOrder: 4,
  ),
  SafetyGuide(
    category: kGuideChild,
    emoji: '🏥',
    title: 'Safe zones near school',
    detail: 'Places a child can run to for help',
    colorHex: 0xFF06D6A0,
    sortOrder: 5,
    steps: [
      'Police Checkpoint — Main Gate Road',
      'City School Office (familiar adults)',
      'DHA Bakery — 24/7 open, always staff',
      'Masjid — always people present',
    ],
  ),
  SafetyGuide(
    category: kGuideChild,
    emoji: '🆘',
    title: 'Child emergency numbers',
    detail: 'Helplines every child should know',
    colorHex: 0xFFE63946,
    sortOrder: 6,
    steps: [
      'Child Helpline — 1121',
      'Police — 15',
      'Edhi Foundation — 115',
      'Madadgar — 1099',
    ],
  ),
];
