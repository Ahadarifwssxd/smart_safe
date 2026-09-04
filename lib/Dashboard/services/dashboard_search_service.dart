import 'package:cloud_firestore/cloud_firestore.dart';

class SearchResultItem {
  final String title;
  final String subtitle;
  final String type;
  final String routeKey;

  const SearchResultItem({
    required this.title,
    required this.subtitle,
    required this.type,
    required this.routeKey,
  });
}

class DashboardSearchService {
  static final DashboardSearchService instance = DashboardSearchService._();
  DashboardSearchService._();

  final _db = FirebaseFirestore.instance;

  Future<List<SearchResultItem>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return [];

    final results = <SearchResultItem>[];

    bool match(String? s) => s != null && s.toLowerCase().contains(q);

    try {
      final users = await _db.collection('users').limit(40).get();
      for (final doc in users.docs) {
        final d = doc.data();
        final name = d['name']?.toString() ?? '';
        final email = d['email']?.toString() ?? '';
        if (match(name) || match(email)) {
          results.add(SearchResultItem(
            title: name.isNotEmpty ? name : email,
            subtitle: email,
            type: 'User',
            routeKey: 'users',
          ));
        }
      }

      final sos = await _db.collection('sos_events').limit(60).get();
      for (final doc in sos.docs) {
        final d = doc.data();
        if (match(d['userName']?.toString()) ||
            match(d['location']?.toString()) ||
            match(d['source']?.toString())) {
          results.add(SearchResultItem(
            title: d['userName']?.toString() ?? 'SOS',
            subtitle: '${d['location']} · ${d['alertType']}',
            type: 'SOS Event',
            routeKey: 'sos_activity',
          ));
        }
      }

      final contacts = await _db.collection('emergency_contacts').limit(60).get();
      for (final doc in contacts.docs) {
        final d = doc.data();
        if (match(d['name']?.toString()) || match(d['phone']?.toString()) || match(d['userName']?.toString())) {
          results.add(SearchResultItem(
            title: d['name']?.toString() ?? 'Contact',
            subtitle: '${d['phone']} · ${d['userName'] ?? ''}',
            type: 'Emergency Contact',
            routeKey: 'emergency_contacts',
          ));
        }
      }

      final alerts = await _db.collection('alerts').limit(40).get();
      for (final doc in alerts.docs) {
        final d = doc.data();
        if (match(d['userName']?.toString()) || match(d['location']?.toString())) {
          results.add(SearchResultItem(
            title: d['userName']?.toString() ?? 'Alert',
            subtitle: d['location']?.toString() ?? '',
            type: 'Alert',
            routeKey: 'alerts',
          ));
        }
      }
    } catch (_) {}

    return results.take(20).toList();
  }
}
