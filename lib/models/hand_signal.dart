/// A single admin-managed "Hand Signal for Help" shown on the Women Safety page.
/// Each signal has a bilingual (EN/UR) title + description, a short spoken line
/// for text-to-speech, and a [motion] key that drives the in-app animated demo.
class HandSignal {
  final String emoji;
  final String titleEn;
  final String titleUr;
  final String descEn;
  final String descUr;
  final String speakEn;
  final String speakUr;

  /// Animation style for the in-app demo:
  /// 'push' | 'fold' | 'raise' | 'call' | 'wave' | 'cross'.
  final String motion;

  final int sortOrder;

  const HandSignal({
    required this.emoji,
    required this.titleEn,
    required this.titleUr,
    required this.descEn,
    required this.descUr,
    required this.speakEn,
    required this.speakUr,
    required this.motion,
    this.sortOrder = 0,
  });

  factory HandSignal.fromMap(Map<String, dynamic> m) => HandSignal(
        emoji: m['emoji']?.toString() ?? '✋',
        titleEn: m['titleEn']?.toString() ?? '',
        titleUr: m['titleUr']?.toString() ?? '',
        descEn: m['descEn']?.toString() ?? '',
        descUr: m['descUr']?.toString() ?? '',
        speakEn: m['speakEn']?.toString() ?? '',
        speakUr: m['speakUr']?.toString() ?? '',
        motion: m['motion']?.toString() ?? 'push',
        sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

// Allowed motion keys (kept as a constant to keep app + dashboard in sync).
// Each key maps to a visually distinct animation in the in-app demo.
const List<String> kHandSignalMotions = [
  'push',
  'fold',
  'raise',
  'count',
  'call',
  'wave',
  'cross',
];

/// The universal "Signal for Help" family — the 5 standard hand signals a woman
/// in danger can flash silently so a bystander knows to help. Seeded into
/// Firestore on first run, and used as the offline fallback when the collection
/// is empty or offline before the first sync — so the page is never blank.
const List<HandSignal> defaultHandSignals = [
  HandSignal(
    emoji: '✋',
    titleEn: '1 · Palm Out',
    titleUr: '۱ · کھلی ہتھیلی',
    descEn: 'Open palm facing out.',
    descUr: 'ہتھیلی سامنے کھلی رکھیں۔',
    speakEn: 'I need help. This is not safe.',
    speakUr: 'مجھے مدد چاہیے، یہ جگہ محفوظ نہیں۔',
    motion: 'push',
    sortOrder: 0,
  ),
  HandSignal(
    emoji: '🤚',
    titleEn: '2 · Thumb Tuck',
    titleUr: '۲ · انگوٹھا اندر',
    descEn: 'Tuck your thumb into your palm.',
    descUr: 'انگوٹھا ہتھیلی کے اندر موڑ لیں۔',
    speakEn: 'I need help, please call the police.',
    speakUr: 'مدد چاہیے، براہِ کرم پولیس کو بلائیں۔',
    motion: 'fold',
    sortOrder: 1,
  ),
  HandSignal(
    emoji: '✊',
    titleEn: '3 · Fist',
    titleUr: '۳ · مُکّا',
    descEn: 'Make a fist with your hand.',
    descUr: 'اپنے ہاتھ کا مُکّا بنائیں۔',
    speakEn: 'I am in danger, please help.',
    speakUr: 'میں خطرے میں ہوں، مدد کریں۔',
    motion: 'raise',
    sortOrder: 2,
  ),
  HandSignal(
    emoji: '🖐️',
    titleEn: '4 · Four Fingers Up',
    titleUr: '۴ · چار انگلیاں اوپر',
    descEn: 'Hold up 4 fingers, thumb folded in.',
    descUr: 'چار انگلیاں اوپر، انگوٹھا اندر موڑا ہوا۔',
    speakEn: 'I need help, but quietly — do not draw attention.',
    speakUr: 'خاموشی سے مدد چاہیے، توجہ نہ دلائیں۔',
    motion: 'count',
    sortOrder: 3,
  ),
  HandSignal(
    emoji: '🤟',
    titleEn: '5 · L-Shape',
    titleUr: '۵ · ایل کی شکل',
    descEn: 'Make an L with your index finger and thumb.',
    descUr: 'شہادت کی انگلی اور انگوٹھے سے L بنائیں۔',
    speakEn: 'I need help, take me to a safe place.',
    speakUr: 'مجھے محفوظ جگہ لے چلیں۔',
    motion: 'call',
    sortOrder: 4,
  ),
];
