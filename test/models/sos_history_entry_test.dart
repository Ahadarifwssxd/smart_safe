import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsafe/models/sos_history_entry.dart';

void main() {
  group('SosHistoryEntry.fromFirestore', () {
    test('reads all fields including a Timestamp createdAt', () {
      final when = DateTime(2026, 6, 27, 9, 5);
      final e = SosHistoryEntry.fromFirestore('id1', {
        'source': 'home_sos_button',
        'location': 'Karachi',
        'alertType': 'SOS',
        'status': 'Active',
        'createdAt': Timestamp.fromDate(when),
      });
      expect(e.id, 'id1');
      expect(e.source, 'home_sos_button');
      expect(e.location, 'Karachi');
      expect(e.createdAt, when);
    });

    test('falls back to defaults when fields are missing', () {
      final e = SosHistoryEntry.fromFirestore('id2', {});
      expect(e.source, 'app');
      expect(e.location, '');
      expect(e.alertType, 'SOS');
      expect(e.status, 'Active');
    });
  });

  group('formatting getters', () {
    final e = SosHistoryEntry(
      id: 'x',
      source: 'app',
      location: '',
      alertType: 'SOS',
      status: 'Active',
      createdAt: DateTime(2026, 6, 27, 9, 5),
    );

    test('formattedDate is "day Mon year"', () {
      expect(e.formattedDate, '27 Jun 2026');
    });

    test('formattedTime is zero-padded HH:mm', () {
      expect(e.formattedTime, '09:05');
    });
  });
}
