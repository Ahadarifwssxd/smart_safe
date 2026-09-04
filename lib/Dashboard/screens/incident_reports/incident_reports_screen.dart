import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smartsafe/utils/error_message.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Pulls "(lat, lon)" coordinates out of a location string (legacy reports that
/// stored the GPS inside the address text). Returns null if none are found.
LatLng? extractLatLng(String locStr) {
  final regExp =
      RegExp(r'\(([-+]?[0-9]*\.?[0-9]+),\s*([-+]?[0-9]*\.?[0-9]+)\)');
  final match = regExp.firstMatch(locStr);
  if (match != null && match.groupCount == 2) {
    final lat = double.tryParse(match.group(1)!);
    final lon = double.tryParse(match.group(2)!);
    if (lat != null && lon != null) return LatLng(lat, lon);
  }
  return null;
}

class IncidentModel {
  String id;
  String user;
  String incidentType;
  String description;
  String location;
  String time;
  String status;
  /// Moderation: 'pending' (needs admin review, hidden from the app),
  /// 'approved' (shown in the app feed) or 'rejected'.
  String moderationStatus;
  /// Admin-set severity: 'urgent' | 'high' | 'normal'.
  String priority;
  /// Real GPS of the report. Newer reports store these directly; older ones only
  /// have coordinates buried in the [location] text, which is why the map used
  /// to point at the wrong place.
  final double? latitude;
  final double? longitude;

  IncidentModel({
    required this.id,
    required this.user,
    required this.incidentType,
    required this.description,
    required this.location,
    required this.time,
    required this.status,
    this.moderationStatus = 'approved',
    this.priority = 'normal',
    this.latitude,
    this.longitude,
  });

  /// The point to plot: the stored coordinates when we have them, otherwise a
  /// best-effort parse of the location text (legacy reports).
  LatLng? get point {
    if (latitude != null && longitude != null) {
      return LatLng(latitude!, longitude!);
    }
    return extractLatLng(location);
  }
}

class IncidentReportsScreen extends StatefulWidget {
  const IncidentReportsScreen({Key? key}) : super(key: key);

  @override
  State<IncidentReportsScreen> createState() => _IncidentReportsScreenState();
}

class _IncidentReportsScreenState extends State<IncidentReportsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  String _selectedType = "Harassment";
  String _selectedStatus = "Reviewing";
  IncidentModel? _editingIncident;

  @override
  void dispose() {
    _userController.dispose();
    _descController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _showIncidentDialog([IncidentModel? incident]) {
    _editingIncident = incident;
    if (incident != null) {
      _userController.text = incident.user;
      _descController.text = incident.description;
      _locationController.text = incident.location;
      _selectedType = incident.incidentType;
      _selectedStatus = incident.status;
    } else {
      _userController.clear();
      _descController.clear();
      _locationController.clear();
      _selectedType = "Harassment";
      _selectedStatus = "Reviewing";
    }

    List<String> types = ["Unsafe Area", "Harassment", "Crash Detection", "Theft", "Medical", "Dark Area", "Accident", "Other"];
    if (incident != null && !types.contains(incident.incidentType)) {
      types.add(incident.incidentType);
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: C.bg2,
              title: Text(incident == null ? "Add Incident Report" : "Edit Incident Report", style: TextStyle(color: C.textPrimary)),
              content: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (extractLatLng(_locationController.text) != null)
                        Container(
                          height: 200,
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 15),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: FlutterMap(
                              options: MapOptions(
                                center: extractLatLng(_locationController.text)!,
                                zoom: 15,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  subdomains: const ['a', 'b', 'c'],
                                  userAgentPackageName: 'com.smartsafe.admin',
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: extractLatLng(_locationController.text)!,
                                      width: 40,
                                      height: 40,
                                      builder: (ctx) => const Icon(Icons.location_on, color: Colors.red, size: 40),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      TextFormField(
                        controller: _userController,
                        style: TextStyle(color: C.textPrimary),
                        decoration: const InputDecoration(labelText: "Reporter Name"),
                        validator: (value) => value == null || value.isEmpty ? "Please enter reporter name" : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _locationController,
                        style: TextStyle(color: C.textPrimary),
                        decoration: const InputDecoration(labelText: "Location"),
                        validator: (value) => value == null || value.isEmpty ? "Please enter incident location" : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _descController,
                        style: TextStyle(color: C.textPrimary),
                        decoration: const InputDecoration(labelText: "Incident Description"),
                        maxLines: 2,
                        validator: (value) => value == null || value.isEmpty ? "Please enter details" : null,
                      ),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        dropdownColor: C.bg2,
                        initialValue: _selectedType,
                        decoration: const InputDecoration(labelText: "Incident Type"),
                        items: types.map((val) {
                          return DropdownMenuItem(value: val, child: Text(val, style: TextStyle(color: C.textPrimary)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => _selectedType = val);
                          }
                        },
                      ),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        dropdownColor: C.bg2,
                        initialValue: _selectedStatus,
                        decoration: const InputDecoration(labelText: "Status"),
                        items: ["Reviewing", "Investigated", "Resolved"].map((val) {
                          return DropdownMenuItem(value: val, child: Text(val, style: TextStyle(color: C.textPrimary)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => _selectedStatus = val);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Cancel", style: TextStyle(color: C.textMuted)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      try {
                        if (_editingIncident == null) {
                          await FirebaseService.instance.addIncidentReport(
                            user: _userController.text,
                            incidentType: _selectedType,
                            description: _descController.text,
                            location: _locationController.text,
                            status: _selectedStatus,
                          );
                        } else {
                          await FirebaseService.instance.updateIncidentReport(
                            _editingIncident!.id,
                            user: _userController.text,
                            incidentType: _selectedType,
                            description: _descController.text,
                            location: _locationController.text,
                            status: _selectedStatus,
                          );
                        }
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(incident == null ? "Incident Report Added" : "Incident Report Updated")),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(friendlyErrorMessage(e))),
                        );
                      }
                    }
                  },
                  child: Text(incident == null ? "Add" : "Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteIncident(IncidentModel incident) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text("Delete Incident Report", style: TextStyle(color: C.textPrimary)),
        content: Text("Are you sure you want to delete this incident report from ${incident.user}?", style: TextStyle(color: C.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () async {
              try {
                await FirebaseService.instance.deleteIncidentReport(incident.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Incident Report Deleted")),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(friendlyErrorMessage(e))),
                );
              }
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  /// Admin accepts a pending report — picks a priority, then it appears in the
  /// public app feed.
  void _approveDialog(IncidentModel incident) {
    String priority = 'normal';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: C.bg2,
          title: Text('Accept report', style: TextStyle(color: C.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('From ${incident.user} — ${incident.incidentType}',
                  style: TextStyle(color: C.textMuted, fontSize: 13)),
              const SizedBox(height: 16),
              Text('Priority', style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...[
                ('urgent', 'Urgent', Colors.red),
                ('high', 'High', Colors.orange),
                ('normal', 'Normal', Colors.blue),
              ].map((p) => RadioListTile<String>(
                    value: p.$1,
                    groupValue: priority,
                    onChanged: (v) => setInner(() => priority = v!),
                    activeColor: p.$3,
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.$2, style: TextStyle(color: C.textPrimary)),
                  )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: C.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: C.success),
              onPressed: () async {
                try {
                  await FirebaseService.instance
                      .approveIncidentReport(incident.id, priority: priority);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Report accepted — now visible in the app')));
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(friendlyErrorMessage(e))));
                  }
                }
              },
              child: const Text('Accept'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rejectIncident(IncidentModel incident) async {
    try {
      await FirebaseService.instance.rejectIncidentReport(incident.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report rejected — hidden from the app')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Header(),
            const SizedBox(height: defaultPadding),
            PageHeaderBar(
              title: "Incident Reports",
              actions: [
                ElevatedButton.icon(
                  onPressed: () => _showIncidentDialog(),
                  icon: const Icon(Icons.note_add_rounded),
                  label: const Text("Add Test Incident"),
                ),
              ],
            ),
            const SizedBox(height: defaultPadding),
            Container(
              padding: const EdgeInsets.all(defaultPadding),
              decoration: BoxDecoration(
                color: secondaryColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: C.border.withValues(alpha: 0.1)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseService.instance.getIncidentReportsStream(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text("No incident reports found.", style: TextStyle(color: Colors.white70)),
                        ),
                      );
                    }

                    final incidents = docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return IncidentModel(
                        id: doc.id,
                        user: data['user'] ?? '',
                        incidentType: data['incidentType'] ?? '',
                        description: data['description'] ?? '',
                        location: data['location'] ?? '',
                        time: data['time'] ?? '',
                        status: data['status'] ?? 'Reviewing',
                        moderationStatus:
                            data['moderationStatus']?.toString() ?? 'approved',
                        priority: data['priority']?.toString() ?? 'normal',
                        latitude: (data['latitude'] as num?)?.toDouble(),
                        longitude: (data['longitude'] as num?)?.toDouble(),
                      );
                    }).toList();

                    // Split: PENDING user reports await review; everything else
                    // (approved / rejected) is a reviewed record.
                    final pending = incidents
                        .where((i) => i.moderationStatus == 'pending')
                        .toList();
                    final reviewed = incidents
                        .where((i) => i.moderationStatus != 'pending')
                        .toList();

                    // Only reviewed (approved/rejected) reports are plotted &
                    // listed below; pending ones live in the Requests section.
                    final plotted =
                        reviewed.where((i) => i.point != null).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Pending Requests (need admin action) ──────────────
                        if (pending.isNotEmpty) ...[
                          _PendingRequests(
                            pending: pending,
                            onAccept: _approveDialog,
                            onReject: _rejectIncident,
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (plotted.isNotEmpty) ...[
                          SizedBox(
                            height: 300,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: FlutterMap(
                                options: MapOptions(
                                  center: plotted.first.point!,
                                  zoom: 11,
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                                    subdomains: const ['a', 'b', 'c', 'd'],
                                    userAgentPackageName: 'smartsafe.app',
                                    keepBuffer: 6,
                                  ),
                                  MarkerLayer(
                                    markers: plotted
                                        .map((i) => Marker(
                                              point: i.point!,
                                              width: 40,
                                              height: 40,
                                              builder: (_) => Tooltip(
                                                message:
                                                    '${i.incidentType} — ${i.location}',
                                                child: Icon(
                                                  Icons.location_on,
                                                  color: i.status == 'Resolved'
                                                      ? Colors.green
                                                      : Colors.red,
                                                  size: 34,
                                                ),
                                              ),
                                            ))
                                        .toList(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${plotted.length} of ${incidents.length} reports have GPS coordinates',
                            style: TextStyle(color: C.textMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                        ],
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                        columnSpacing: dataTableColumnSpacing(context),
                        headingTextStyle: TextStyle(
                            color: C.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 13),
                        columns: const [
                          DataColumn(label: Text("Reporter")),
                          DataColumn(label: Text("Incident Type")),
                          DataColumn(label: Text("Location")),
                          DataColumn(label: Text("Time")),
                          DataColumn(label: Text("Review")),
                          DataColumn(label: Text("Status")),
                          DataColumn(label: Text("Actions")),
                        ],
                        rows: reviewed.map((incident) {
                          return DataRow(
                            cells: [
                              DataCell(Text(incident.user, style: TextStyle(color: C.textPrimary))),
                              DataCell(Text(incident.incidentType, style: TextStyle(color: C.textMuted))),
                              DataCell(Text(incident.location, style: TextStyle(color: C.textMuted))),
                              DataCell(Text(incident.time, style: TextStyle(color: C.textMuted))),
                              DataCell(_ModerationBadge(
                                  moderation: incident.moderationStatus,
                                  priority: incident.priority)),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: incident.status == "Resolved"
                                        ? C.success.withValues(alpha: 0.15)
                                        : incident.status == "Investigated"
                                            ? C.accent.withValues(alpha: 0.15)
                                            : C.accent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    incident.status,
                                    style: TextStyle(
                                      color: incident.status == "Resolved"
                                          ? C.success
                                          : incident.status == "Investigated"
                                              ? C.accent
                                              : C.accentLight,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  children: [
                                    // Accept / Reject only make sense for a
                                    // report still awaiting review.
                                    if (incident.moderationStatus == 'pending') ...[
                                      IconButton(
                                        tooltip: 'Accept (show in app)',
                                        icon: Icon(Icons.check_circle,
                                            color: C.success, size: 22),
                                        onPressed: () => _approveDialog(incident),
                                      ),
                                      IconButton(
                                        tooltip: 'Reject',
                                        icon: Icon(Icons.cancel,
                                            color: C.warning, size: 22),
                                        onPressed: () => _rejectIncident(incident),
                                      ),
                                    ],
                                    IconButton(
                                      icon: Icon(Icons.edit, color: C.accent, size: 20),
                                      onPressed: () => _showIncidentDialog(incident),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete, color: C.accent, size: 20),
                                      onPressed: () => _deleteIncident(incident),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a report's moderation state — PENDING (needs review), APPROVED (with
/// its Urgent/High/Normal priority) or REJECTED.
class _ModerationBadge extends StatelessWidget {
  final String moderation;
  final String priority;
  const _ModerationBadge({required this.moderation, required this.priority});

  @override
  Widget build(BuildContext context) {
    late Color color;
    late String label;
    if (moderation == 'pending') {
      color = Colors.amber;
      label = 'PENDING';
    } else if (moderation == 'rejected') {
      color = Colors.grey;
      label = 'REJECTED';
    } else {
      // approved → show the priority
      switch (priority) {
        case 'urgent':
          color = Colors.red;
          label = 'URGENT';
          break;
        case 'high':
          color = Colors.orange;
          label = 'HIGH';
          break;
        default:
          color = Colors.green;
          label = 'APPROVED';
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Highlighted "Pending Requests" section — user-submitted reports awaiting
/// admin action. Accepting one makes it public in the app (and plots it on the
/// map/feed); rejecting hides it.
class _PendingRequests extends StatelessWidget {
  final List<IncidentModel> pending;
  final void Function(IncidentModel) onAccept;
  final Future<void> Function(IncidentModel) onReject;
  const _PendingRequests({
    required this.pending,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(defaultPadding),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_rounded,
                  color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text('Pending Requests (${pending.length})',
                  style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ],
          ),
          const SizedBox(height: 4),
          Text('New user reports — accept to publish to the app, or reject.',
              style: TextStyle(color: C.textMuted, fontSize: 12)),
          const SizedBox(height: 12),
          ...pending.map((i) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: secondaryColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: C.border.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(i.incidentType,
                                style: TextStyle(
                                    color: C.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            const SizedBox(width: 8),
                            Text('· ${i.user}',
                                style: TextStyle(
                                    color: C.textMuted, fontSize: 11)),
                          ]),
                          const SizedBox(height: 3),
                          Text(i.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(color: C.textMuted, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(i.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: C.textDim, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: C.success,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8)),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Accept'),
                      onPressed: () => onAccept(i),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: C.warning,
                          side: BorderSide(color: C.warning),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8)),
                      onPressed: () => onReject(i),
                      child: const Text('Reject'),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
