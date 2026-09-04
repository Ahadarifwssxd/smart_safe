import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:smartsafe/widgets/osm_map_widget.dart';
import 'package:smartsafe/Dashboard/responsive.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import '../../../constants.dart';

class LiveUsersLocation extends StatefulWidget {
  const LiveUsersLocation({Key? key}) : super(key: key);

  @override
  State<LiveUsersLocation> createState() => _LiveUsersLocationState();
}

class _LiveUsersLocationState extends State<LiveUsersLocation> {
  final Map<String, String> _addressCache = {};
  final Set<String> _addressRequestsInProgress = {};

  String _formatTime(dynamic ts) {
    if (ts == null) return 'Never';
    if (ts is! Timestamp) return 'Active';
    final dt = ts.toDate();
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<String> _getAddressForUser(
      String userId, double lat, double lon) async {
    if (_addressCache.containsKey(userId)) {
      return _addressCache[userId]!;
    }
    if (_addressRequestsInProgress.contains(userId)) {
      return 'Loading address...';
    }

    _addressRequestsInProgress.add(userId);
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json&accept-language=en');
      final response =
          await http.get(url, headers: {'User-Agent': 'SmartSafeApp/1.0'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final parts = [
            address['house_number'],
            address['road'],
            address['suburb'] ?? address['neighbourhood'],
            address['city'] ?? address['town'] ?? address['village'],
            address['state'],
            address['postcode'],
          ].whereType<String>().toList();
          final placeName = parts.isNotEmpty
              ? parts.join(', ')
              : (data['display_name'] ?? 'Unknown location');
          _addressCache[userId] = placeName;
          return placeName;
        }
        return data['display_name'] ?? 'Unknown location';
      }
    } catch (_) {}
    return 'Unable to resolve address';
  }

  void _showMapDialog(BuildContext context, String userName, String userId,
      double lat, double lon) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: C.bg2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: C.border),
          ),
          title: Row(
            children: [
              Icon(Icons.location_on_rounded, color: C.accent, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "$userName's Live Location",
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: min(MediaQuery.of(context).size.width * 0.8, 650),
            height: min(MediaQuery.of(context).size.height * 0.7, 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: OsmMapWidget.create(latitude: lat, longitude: lon),
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<String>(
                  future: _getAddressForUser(userId, lat, lon),
                  builder: (context, snapshot) {
                    final address = snapshot.data ?? 'Loading address...';
                    return Text(
                      address,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                      textAlign: TextAlign.left,
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close",
                  style:
                      TextStyle(color: C.textMuted, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(defaultPadding),
      decoration: BoxDecoration(
        color: secondaryColor,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.radar_rounded, color: C.accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Live User Locations & Telemetry",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: defaultPadding),
          SizedBox(
            width: double.infinity,
            child: StreamBuilder<QuerySnapshot>(
              // Cap the live stream so the dashboard stays light even with a
              // large user base (the map only needs a sample of recent users).
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                // Filter for users actively sharing their location
                final activeUsers = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['isLocationSharingActive'] == true &&
                      data['latitude'] != null &&
                      data['longitude'] != null;
                }).toList();

                if (activeUsers.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_off_rounded,
                              color: Colors.white24, size: 40),
                          SizedBox(height: 10),
                          Text(
                            "No users currently broadcasting live location.",
                            style:
                                TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: dataTableColumnSpacing(context),
                    columns: const [
                      DataColumn(label: Text("User")),
                      DataColumn(label: Text("Address")),
                      DataColumn(label: Text("Coordinates")),
                      DataColumn(label: Text("Accuracy")),
                      DataColumn(label: Text("Speed")),
                      DataColumn(label: Text("Last Updated")),
                      DataColumn(label: Text("Map View")),
                    ],
                    rows: activeUsers.map((doc) {
                      final userId = doc.id;
                      final data = doc.data() as Map<String, dynamic>;
                      final userName = data['name']?.toString() ?? 'Anonymous';
                      final email = data['email']?.toString() ?? '';
                      final lat = (data['latitude'] as num).toDouble();
                      final lon = (data['longitude'] as num).toDouble();
                      final accuracy =
                          (data['accuracy'] as num?)?.toDouble() ?? 0.0;
                      final speed = (data['speed'] as num?)?.toDouble() ?? 0.0;
                      final lastUpdated = data['lastLocationUpdate'];

                      return DataRow(
                        cells: [
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: C.success,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(userName,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                if (email.isNotEmpty)
                                  Text(email,
                                      style: TextStyle(
                                          color: C.textMuted, fontSize: 10)),
                              ],
                            ),
                          ),
                          DataCell(
                            FutureBuilder<String>(
                              future: _getAddressForUser(userId, lat, lon),
                              builder: (context, snapshot) {
                                final address =
                                    snapshot.data ?? 'Resolving address...';
                                return SizedBox(
                                  width:
                                      Responsive.isMobile(context) ? 170 : 240,
                                  child: Text(
                                    address,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              },
                            ),
                          ),
                          DataCell(Text(
                            "${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°",
                            style: const TextStyle(color: Colors.white70),
                          )),
                          DataCell(Text(
                            "±${accuracy.toStringAsFixed(1)} m",
                            style: const TextStyle(color: Colors.white70),
                          )),
                          DataCell(Text(
                            "${speed.toStringAsFixed(1)} km/h",
                            style: const TextStyle(color: Colors.white70),
                          )),
                          DataCell(Text(
                            _formatTime(lastUpdated),
                            style: const TextStyle(color: Colors.white70),
                          )),
                          DataCell(
                            ElevatedButton.icon(
                              onPressed: () => _showMapDialog(
                                  context, userName, userId, lat, lon),
                              icon: const Icon(Icons.map_rounded, size: 14),
                              label: const Text("View Map",
                                  style: TextStyle(fontSize: 11)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: C.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Math helper for double constraint formatting
double min(double a, double b) => a < b ? a : b;
