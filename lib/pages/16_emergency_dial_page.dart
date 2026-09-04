import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import '../Dashboard/services/firebase_service.dart';
import '../services/page_content_service.dart';
import '../theme/colors.dart';
import '../widgets/responsive.dart';
import '../widgets/widgets.dart';

/// One emergency helpline shown on the dial page.
class _DialNumber {
  final String label;
  final String number;
  final String sub;
  final IconData icon;
  final Color color;
  const _DialNumber(this.label, this.number, this.sub, this.icon, this.color);
}

/// Maps the admin-chosen [iconKey] string (stored in Firestore) to an icon.
IconData _iconFor(String key) {
  switch (key) {
    case 'hospital':
      return Icons.local_hospital_rounded;
    case 'police':
      return Icons.local_police_rounded;
    case 'support':
      return Icons.support_agent_rounded;
    case 'emergency':
      return Icons.emergency_rounded;
    case 'child':
      return Icons.child_care_rounded;
    case 'fire':
      return Icons.local_fire_department_rounded;
    case 'security':
      return Icons.security_rounded;
    case 'rescue':
      return Icons.fire_truck_rounded;
    case 'psychology':
      return Icons.psychology_rounded;
    case 'hearing':
      return Icons.hearing_disabled_rounded;
    default:
      return Icons.phone_in_talk_rounded;
  }
}

class EmergencyDialPage extends StatelessWidget {
  const EmergencyDialPage({super.key});

  /// Offline fallback — used when Firestore has no admin-managed numbers yet
  /// (or the device is offline before the first sync). These are Pakistan's
  /// national helplines so the page is never empty in an emergency.
  static final _fallback = <_DialNumber>[
    _DialNumber('Ambulance', '1122', 'Rescue & Emergency Service',
        Icons.local_hospital_rounded, AppColors.red),
    _DialNumber('Police', '15', 'Pakistan Police Emergency',
        Icons.local_police_rounded, AppColors.red),
    _DialNumber('Madadgar', '1099', 'Women & Child Safety Helpline',
        Icons.support_agent_rounded, AppColors.red),
    _DialNumber('Edhi Foundation', '115', 'Free ambulance nationwide',
        Icons.emergency_rounded, AppColors.success),
    _DialNumber('Child Helpline', '1121', 'Child abuse & protection',
        Icons.child_care_rounded, AppColors.accent),
    _DialNumber('Fire Brigade', '16', 'Fire emergency',
        Icons.local_fire_department_rounded, AppColors.accent),
    _DialNumber('Rozan Counseling', '0800-22444', 'Free counseling & support',
        Icons.psychology_rounded, AppColors.accent),
    _DialNumber('CPLC', '021-35662000', 'Crime reporting Karachi',
        Icons.security_rounded, AppColors.accent),
  ];

  Future<void> _makeCall(BuildContext context, String number) async {
    // Strip formatting (dashes/spaces) and place a REAL direct call.
    final clean = number.replaceAll(RegExp(r'[^0-9+]'), '');
    try {
      await FlutterPhoneDirectCaller.callNumber(clean);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: C.accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Text('Could not place the call to $number',
              style: TextStyle(color: C.textPrimary)),
        ));
      }
    }
  }

  /// Maps admin-managed Firestore docs to the dial list, sorted by sortOrder.
  List<_DialNumber> _fromDocs(List<QueryDocumentSnapshot> docs) {
    final list = docs
        .map((d) => d.data() as Map<String, dynamic>)
        .where((m) => m['active'] != false)
        .toList()
      ..sort((a, b) =>
          (a['sortOrder'] ?? 0).compareTo(b['sortOrder'] ?? 0));
    return list.map((m) {
      final colorHex = (m['colorHex'] as num?)?.toInt() ?? 0xFFE63946;
      return _DialNumber(
        m['label']?.toString() ?? 'Helpline',
        m['number']?.toString() ?? '',
        m['description']?.toString() ?? '',
        _iconFor(m['iconKey']?.toString() ?? 'phone'),
        Color(colorHex),
      );
    }).where((n) => n.number.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        body: SafeArea(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.instance.getEmergencyNumbersStream(),
            builder: (context, snap) {
              final numbers = (snap.hasData && snap.data!.docs.isNotEmpty)
                  ? _fromDocs(snap.data!.docs)
                  : _fallback;
              final top = numbers.take(3).toList();
              return Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: responsiveHInset(context), vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (Navigator.canPop(context)) ...[
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Icon(Icons.arrow_back_ios_new_rounded,
                              color: C.textPrimary, size: 18),
                        ),
                        const SizedBox(width: 12),
                      ],
                      DynText('emergency_dial', 'title', 'Emergency Contacts',
                          style: TextStyle(
                              color: C.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2)),
                    ]),
                    const SizedBox(height: 4),
                    Text('One tap to call — saved for offline use',
                        style: TextStyle(color: C.textMuted, fontSize: 12)),
                    const SizedBox(height: 16),

                    // Top 3 big buttons (first three admin-ordered numbers).
                    if (top.isNotEmpty)
                      Row(children: [
                        for (var i = 0; i < top.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          _BigDial(
                            label: top[i].label,
                            number: top[i].number,
                            color: top[i].color,
                            icon: top[i].icon,
                            onTap: () => _makeCall(context, top[i].number),
                          ),
                        ],
                      ]),

                    const SizedBox(height: 24),
                    const SecHeader('All emergency numbers'),
                    const SizedBox(height: 12),

                    Expanded(
                      child: ListView.separated(
                        itemCount: numbers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final n = numbers[i];
                          return SlideUpFade(
                            delay: Duration(milliseconds: i * 40),
                            child: GestureDetector(
                              onTap: () => _makeCall(context, n.number),
                              child: DCard(
                                  child: Row(children: [
                                Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                        color: n.color.withValues(alpha: .15),
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Icon(n.icon,
                                        color: n.color, size: 22)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(n.label,
                                          style: TextStyle(
                                              color: C.textPrimary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700)),
                                      Text(n.sub,
                                          style: TextStyle(
                                              color: C.textMuted,
                                              fontSize: 11)),
                                    ])),
                                Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(n.number,
                                          style: TextStyle(
                                              color: n.color,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 4),
                                      Container(
                                          width: 36,
                                          height: 28,
                                          decoration: BoxDecoration(
                                              color: n.color.withValues(alpha: .15),
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                          child: Icon(Icons.call_rounded,
                                              color: n.color, size: 16)),
                                    ]),
                              ])),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 12),
                    DCard(
                        borderColor: C.accent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(children: [
                          Icon(Icons.wifi_off_rounded,
                              color: C.accent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  'All numbers work without internet. Saved locally on your phone.',
                                  style: TextStyle(
                                      color: C.textMuted, fontSize: 11))),
                        ])),
                    const SizedBox(height: 12),
                  ],
                ),
              );
            },
          ),
        ),
      );
}

class _BigDial extends StatelessWidget {
  final String label, number;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _BigDial(
      {required this.label,
      required this.number,
      required this.color,
      required this.icon,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
          child: GestureDetector(
        onTap: onTap,
        child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: .4))),
            child: Column(children: [
              Container(
                  width: 44,
                  height: 44,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: color),
                  child: Icon(icon, color: Colors.white, size: 22)),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(number,
                    style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
              ),
              Text(label,
                  style: TextStyle(color: C.textMuted, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ])),
      ));
}
