import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/responsive.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smartsafe/utils/error_message.dart';

class DangerZoneModel {
  String id;
  String name;
  String riskLevel;
  String coordinates;
  String safetyAdvice;
  String moderationStatus; // pending | approved | rejected
  String user;

  DangerZoneModel({
    required this.id,
    required this.name,
    required this.riskLevel,
    required this.coordinates,
    required this.safetyAdvice,
    this.moderationStatus = 'approved',
    this.user = '',
  });
}

class DangerZonesScreen extends StatefulWidget {
  const DangerZonesScreen({Key? key}) : super(key: key);

  @override
  State<DangerZonesScreen> createState() => _DangerZonesScreenState();
}

class _DangerZonesScreenState extends State<DangerZonesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _coordsController = TextEditingController();
  final _adviceController = TextEditingController();
  String _selectedRiskLevel = "High";
  DangerZoneModel? _editingZone;

  @override
  void dispose() {
    _nameController.dispose();
    _coordsController.dispose();
    _adviceController.dispose();
    super.dispose();
  }

  void _showZoneDialog([DangerZoneModel? zone]) {
    _editingZone = zone;
    if (zone != null) {
      _nameController.text = zone.name;
      _coordsController.text = zone.coordinates;
      _adviceController.text = zone.safetyAdvice;
      _selectedRiskLevel = zone.riskLevel;
    } else {
      _nameController.clear();
      _coordsController.clear();
      _adviceController.clear();
      _selectedRiskLevel = "High";
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: C.bg2,
              title: Text(zone == null ? "Add Danger Zone" : "Edit Danger Zone", style: TextStyle(color: C.textPrimary)),
              content: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(color: C.textPrimary),
                        decoration: const InputDecoration(labelText: "Zone Name/Location"),
                        validator: (value) => value == null || value.isEmpty ? "Please enter a name" : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _coordsController,
                        style: TextStyle(color: C.textPrimary),
                        decoration: const InputDecoration(labelText: "Coordinates (Lat, Lng)"),
                        validator: (value) => value == null || value.isEmpty ? "Please enter coordinates" : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _adviceController,
                        style: TextStyle(color: C.textPrimary),
                        decoration: const InputDecoration(labelText: "Safety Advice"),
                        maxLines: 2,
                        validator: (value) => value == null || value.isEmpty ? "Please enter safety advice" : null,
                      ),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        dropdownColor: C.bg2,
                        initialValue: _selectedRiskLevel,
                        decoration: const InputDecoration(labelText: "Risk Level"),
                        items: ["High", "Medium", "Low"].map((val) {
                          return DropdownMenuItem(value: val, child: Text(val, style: TextStyle(color: C.textPrimary)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => _selectedRiskLevel = val);
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
                        if (_editingZone == null) {
                          await FirebaseService.instance.addDangerZone(
                            name: _nameController.text,
                            coordinates: _coordsController.text,
                            safetyAdvice: _adviceController.text,
                            riskLevel: _selectedRiskLevel,
                          );
                        } else {
                          await FirebaseService.instance.updateDangerZone(
                            _editingZone!.id,
                            name: _nameController.text,
                            coordinates: _coordsController.text,
                            safetyAdvice: _adviceController.text,
                            riskLevel: _selectedRiskLevel,
                          );
                        }
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(zone == null ? "Danger Zone Added" : "Danger Zone Updated")),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(friendlyErrorMessage(e))),
                        );
                      }
                    }
                  },
                  child: Text(zone == null ? "Add" : "Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteZone(DangerZoneModel zone) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text("Delete Danger Zone", style: TextStyle(color: C.textPrimary)),
        content: Text("Are you sure you want to delete ${zone.name}?", style: TextStyle(color: C.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () async {
              try {
                await FirebaseService.instance.deleteDangerZone(zone.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Danger Zone Deleted")),
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

  Future<void> _approve(DangerZoneModel zone) async {
    try {
      await FirebaseService.instance.approveDangerZone(zone.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Danger zone accepted — now visible in the app.")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _reject(DangerZoneModel zone) async {
    try {
      await FirebaseService.instance.rejectDangerZone(zone.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Danger zone rejected — hidden from the app.")));
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
              title: "Danger Zones",
              subtitle:
                  "User-reported zones need approval before they show in the app.",
              actions: [
                ElevatedButton.icon(
                  onPressed: () => _showZoneDialog(),
                  icon: const Icon(Icons.add_location_alt_rounded),
                  label: const Text("Add Danger Zone"),
                ),
              ],
            ),
            const SizedBox(height: defaultPadding),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.instance.getDangerZonesStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final zones = snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return DangerZoneModel(
                    id: doc.id,
                    name: data['name'] ?? '',
                    coordinates: data['coordinates'] ?? '',
                    safetyAdvice: data['safetyAdvice'] ?? '',
                    riskLevel: data['riskLevel'] ?? 'Low',
                    moderationStatus:
                        (data['moderationStatus'] ?? 'approved').toString(),
                    user: (data['user'] ?? '').toString(),
                  );
                }).toList();

                final pending = zones
                    .where((z) => z.moderationStatus == 'pending')
                    .toList();
                final reviewed = zones
                    .where((z) => z.moderationStatus != 'pending')
                    .toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pending.isNotEmpty) ...[
                      _PendingRequests(
                        pending: pending,
                        onAccept: _approve,
                        onReject: _reject,
                      ),
                      const SizedBox(height: defaultPadding),
                    ],
                    Container(
                      padding: const EdgeInsets.all(defaultPadding),
                      decoration: BoxDecoration(
                        color: secondaryColor,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: C.border.withValues(alpha: 0.1)),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: reviewed.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                      pending.isEmpty
                                          ? "No danger zones found."
                                          : "No approved zones yet — review the pending requests above.",
                                      style: TextStyle(color: C.textMuted)),
                                ),
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columnSpacing:
                                      dataTableColumnSpacing(context),
                                  columns: const [
                                    DataColumn(label: Text("Zone Name")),
                                    DataColumn(label: Text("Risk Level")),
                                    DataColumn(label: Text("Status")),
                                    DataColumn(label: Text("Coordinates")),
                                    DataColumn(label: Text("Safety Advice")),
                                    DataColumn(label: Text("Actions")),
                                  ],
                                  rows: reviewed.map((zone) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(zone.name,
                                            style: TextStyle(
                                                color: C.textPrimary))),
                                        DataCell(_riskBadge(zone.riskLevel)),
                                        DataCell(_statusBadge(
                                            zone.moderationStatus)),
                                        DataCell(Text(zone.coordinates,
                                            style: TextStyle(
                                                color: C.textMuted))),
                                        DataCell(
                                          SizedBox(
                                            width: Responsive.isMobile(context)
                                                ? 150
                                                : 220,
                                            child: Text(
                                              zone.safetyAdvice,
                                              style: TextStyle(
                                                  color: C.textMuted),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Row(
                                            children: [
                                              IconButton(
                                                icon: Icon(Icons.edit,
                                                    color: C.accent, size: 20),
                                                onPressed: () =>
                                                    _showZoneDialog(zone),
                                              ),
                                              IconButton(
                                                icon: Icon(Icons.delete,
                                                    color: C.red, size: 20),
                                                onPressed: () =>
                                                    _deleteZone(zone),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _riskBadge(String risk) {
    final color = risk == "High"
        ? C.red
        : (risk == "Medium" ? C.warning : C.accent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(risk,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _statusBadge(String status) {
    final approved = status == 'approved';
    final color = approved ? C.success : C.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(approved ? 'APPROVED' : 'REJECTED',
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

/// Amber "needs review" panel listing user-reported danger zones awaiting an
/// admin decision. Mirrors the Incident Reports pending workflow.
class _PendingRequests extends StatelessWidget {
  final List<DangerZoneModel> pending;
  final Future<void> Function(DangerZoneModel) onAccept;
  final Future<void> Function(DangerZoneModel) onReject;

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
        color: C.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pending_actions_rounded, color: C.warning, size: 20),
              const SizedBox(width: 8),
              Text("Pending Requests (${pending.length})",
                  style: TextStyle(
                      color: C.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          Text("Approve to show in the app, or reject to keep it hidden.",
              style: TextStyle(color: C.textMuted, fontSize: 12)),
          const SizedBox(height: 12),
          ...pending.map((z) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: secondaryColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: C.border.withValues(alpha: 0.12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(z.name.isEmpty ? 'Unsafe Area' : z.name,
                              style: TextStyle(
                                  color: C.textPrimary,
                                  fontWeight: FontWeight.w700)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (z.riskLevel == 'High'
                                    ? C.red
                                    : (z.riskLevel == 'Medium'
                                        ? C.warning
                                        : C.accent))
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(z.riskLevel,
                              style: TextStyle(
                                  color: z.riskLevel == 'High'
                                      ? C.red
                                      : (z.riskLevel == 'Medium'
                                          ? C.warning
                                          : C.accent),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(z.safetyAdvice,
                        style: TextStyle(color: C.textMuted, fontSize: 12),
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.place_outlined,
                            color: C.textMuted, size: 13),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(z.coordinates,
                              style: TextStyle(
                                  color: C.textMuted, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (z.user.isNotEmpty) ...[
                          Icon(Icons.person_outline,
                              color: C.textMuted, size: 13),
                          const SizedBox(width: 3),
                          Text(z.user,
                              style: TextStyle(
                                  color: C.textMuted, fontSize: 11)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: C.red,
                              side: BorderSide(
                                  color: C.red.withValues(alpha: 0.5))),
                          onPressed: () => onReject(z),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: const Text("Reject"),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: C.success),
                          onPressed: () => onAccept(z),
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text("Accept"),
                        ),
                      ],
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
