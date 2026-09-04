import 'package:flutter/material.dart';

/// Maps a legacy emoji (stored in Firestore content like safety tips, guides,
/// hand-signals) to a clean single-colour Material icon, so the UI shows
/// professional iconography instead of multicolour emoji glyphs.
///
/// Falls back to a neutral "tip" icon for anything unmapped.
IconData iconForEmoji(String? emoji) {
  final e = (emoji ?? '').trim();
  if (e.isEmpty) return Icons.tips_and_updates_rounded;

  // Match on the first rune so variation selectors / trailing text don't break it.
  final key = String.fromCharCode(e.runes.first);

  switch (key) {
    case '🌙':
    case '🌚':
    case '🌛':
      return Icons.nightlight_round;
    case '📱':
    case '📲':
      return Icons.smartphone_rounded;
    case '🚗':
    case '🚙':
    case '🏎':
      return Icons.directions_car_rounded;
    case '🚑':
      return Icons.local_hospital_rounded;
    case '🚓':
    case '👮':
      return Icons.local_police_rounded;
    case '💡':
      return Icons.lightbulb_rounded;
    case '🛡':
      return Icons.shield_rounded;
    case '⚠':
    case '❗':
    case '‼':
      return Icons.warning_amber_rounded;
    case '🚨':
    case '🆘':
      return Icons.sos_rounded;
    case '📍':
    case '🧭':
      return Icons.location_on_rounded;
    case '❤':
    case '💛':
    case '💚':
    case '💙':
    case '🧡':
      return Icons.favorite_rounded;
    case '🔋':
      return Icons.battery_full_rounded;
    case '🔦':
      return Icons.flashlight_on_rounded;
    case '📞':
    case '☎':
    case '📟':
      return Icons.call_rounded;
    case '👨‍👩‍👧':
    case '👪':
    case '👥':
    case '👩':
      return Icons.groups_rounded;
    case '🧒':
    case '👶':
      return Icons.child_care_rounded;
    case '🏫':
      return Icons.school_rounded;
    case '🎒':
      return Icons.backpack_rounded;
    case '🥊':
      return Icons.sports_mma_rounded;
    case '✋':
    case '🖐':
    case '🤚':
      return Icons.back_hand_rounded;
    case '👁':
    case '👀':
      return Icons.visibility_rounded;
    case '🔑':
      return Icons.vpn_key_rounded;
    case '📌':
      return Icons.push_pin_rounded;
    case '✅':
    case '✔':
      return Icons.check_circle_rounded;
    case '⏱':
    case '⏰':
    case '⌛':
      return Icons.timer_rounded;
    case '💊':
      return Icons.medication_rounded;
    case '🩹':
    case '🏥':
      return Icons.medical_services_rounded;
    default:
      return Icons.tips_and_updates_rounded;
  }
}
