import 'package:cloud_firestore/cloud_firestore.dart';

class SosHistoryEntry {
  final String id;
  final String source;
  final String location;
  final String alertType;
  final String status;
  final DateTime createdAt;

  const SosHistoryEntry({
    required this.id,
    required this.source,
    required this.location,
    required this.alertType,
    required this.status,
    required this.createdAt,
  });

  factory SosHistoryEntry.fromFirestore(String id, Map<String, dynamic> d) {
    final ts = d['createdAt'];
    DateTime time = DateTime.now();
    if (ts is Timestamp) time = ts.toDate();

    return SosHistoryEntry(
      id: id,
      source: d['source']?.toString() ?? 'app',
      location: d['location']?.toString() ?? '',
      alertType: d['alertType']?.toString() ?? 'SOS',
      status: d['status']?.toString() ?? 'Active',
      createdAt: time,
    );
  }

  String get formattedDate {
    final d = createdAt;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String get formattedTime {
    final h = createdAt.hour.toString().padLeft(2, '0');
    final m = createdAt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
