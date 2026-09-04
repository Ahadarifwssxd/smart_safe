import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smartsafe/utils/error_message.dart';

class AlertLogModel {
  String id;
  String userName;
  String alertType;
  String time;
  String location;
  String status;

  AlertLogModel({
    required this.id,
    required this.userName,
    required this.alertType,
    required this.time,
    required this.location,
    required this.status,
  });
}

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({Key? key}) : super(key: key);

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  String _selectedType = "Critical SOS";
  String _selectedStatus = "Active";
  AlertLogModel? _editingAlert;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _showAlertLogDialog([AlertLogModel? alert]) {
    _editingAlert = alert;
    if (alert != null) {
      _nameController.text = alert.userName;
      _locationController.text = alert.location;
      _selectedType = alert.alertType;
      _selectedStatus = alert.status;
    } else {
      _nameController.clear();
      _locationController.clear();
      _selectedType = "Critical SOS";
      _selectedStatus = "Active";
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: C.bg2,
              title: Text(alert == null ? "Add Test Alert" : "Edit Alert Log", style: TextStyle(color: C.textPrimary)),
              content: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(color: C.textPrimary),
                        decoration: const InputDecoration(labelText: "User Name"),
                        validator: (value) => value == null || value.isEmpty ? "Please enter user name" : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _locationController,
                        style: TextStyle(color: C.textPrimary),
                        decoration: const InputDecoration(labelText: "Coordinates/Location"),
                        validator: (value) => value == null || value.isEmpty ? "Please enter location" : null,
                      ),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        dropdownColor: C.bg2,
                        initialValue: _selectedType,
                        decoration: const InputDecoration(labelText: "Alert Type"),
                        items: ["Critical SOS", "Silent SOS", "Crash Detected", "Medical Emergency"].map((val) {
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
                        items: ["Active", "Resolved"].map((val) {
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
                        if (_editingAlert == null) {
                          await FirebaseService.instance.triggerAlert(
                            userName: _nameController.text,
                            alertType: _selectedType,
                            location: _locationController.text,
                            status: _selectedStatus,
                          );
                        } else {
                          await FirebaseService.instance.updateAlertDetails(
                            _editingAlert!.id,
                            userName: _nameController.text,
                            alertType: _selectedType,
                            location: _locationController.text,
                            status: _selectedStatus,
                          );
                        }
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(alert == null ? "Alert Log Created" : "Alert Log Updated")),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(friendlyErrorMessage(e))),
                        );
                      }
                    }
                  },
                  child: Text(alert == null ? "Trigger" : "Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteAlert(AlertLogModel alert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text("Delete Alert Log", style: TextStyle(color: C.textPrimary)),
        content: Text("Are you sure you want to delete this alert log?", style: TextStyle(color: C.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () async {
              try {
                await FirebaseService.instance.deleteAlert(alert.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Alert Log Deleted")),
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
              title: "Emergency SOS Alerts",
              actions: [
                ElevatedButton.icon(
                  onPressed: () => _showAlertLogDialog(),
                  icon: const Icon(Icons.warning_rounded),
                  label: const Text("Add Test Alert"),
                  style: ElevatedButton.styleFrom(backgroundColor: C.accent),
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
                  stream: FirebaseService.instance.getAlertsStream(),
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
                          child: Text("No alert logs found.", style: TextStyle(color: Colors.white70)),
                        ),
                      );
                    }

                    final alerts = docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return AlertLogModel(
                        id: doc.id,
                        userName: data['userName'] ?? 'Unknown User',
                        alertType: data['alertType'] ?? 'Critical SOS',
                        time: data['time'] ?? '',
                        location: data['location'] ?? '',
                        status: data['status'] ?? 'Active',
                      );
                    }).toList();

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                      columnSpacing: dataTableColumnSpacing(context),
                      columns: const [
                        DataColumn(label: Text("User")),
                        DataColumn(label: Text("Alert Type")),
                        DataColumn(label: Text("Time")),
                        DataColumn(label: Text("Location")),
                        DataColumn(label: Text("Status")),
                        DataColumn(label: Text("Actions")),
                      ],
                      rows: alerts.map((alert) {
                        return DataRow(
                          cells: [
                            DataCell(Text(alert.userName, style: TextStyle(color: C.textPrimary))),
                            DataCell(
                              Row(
                                children: [
                                  Icon(
                                    alert.alertType == "Critical SOS" || alert.alertType == "Crash Detected"
                                        ? Icons.error_rounded
                                        : Icons.warning_rounded,
                                    color: alert.alertType == "Critical SOS" || alert.alertType == "Crash Detected"
                                        ? C.accent
                                        : C.warning,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(alert.alertType, style: TextStyle(color: C.textPrimary, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            DataCell(Text(alert.time, style: TextStyle(color: C.textMuted))),
                            DataCell(Text(alert.location, style: TextStyle(color: C.textMuted))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: alert.status == "Active"
                                      ? C.accent.withValues(alpha: 0.15)
                                      : C.success.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  alert.status,
                                  style: TextStyle(
                                    color: alert.status == "Active" ? C.accentLight : C.success,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                children: [
                                  if (alert.status == "Active")
                                    TextButton(
                                      onPressed: () async {
                                        try {
                                          await FirebaseService.instance.updateAlertStatus(alert.id, "Resolved");
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("Alert status set to Resolved")),
                                          );
                                        } catch (e) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(friendlyErrorMessage(e, prefix: 'Could not update status:')))
                                          );
                                        }
                                      },
                                      child: Text("Resolve", style: TextStyle(color: C.success)),
                                    ),
                                  IconButton(
                                    icon: Icon(Icons.edit, color: C.accent, size: 20),
                                    onPressed: () => _showAlertLogDialog(alert),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete, color: C.accent, size: 20),
                                    onPressed: () => _deleteAlert(alert),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ));
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
