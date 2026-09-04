import 'package:flutter/material.dart';
import 'package:smartsafe/Dashboard/constants.dart';
import 'package:smartsafe/Dashboard/screens/dashboard/components/header.dart';
import 'package:smartsafe/Dashboard/widgets/page_header_bar.dart';
import 'package:smartsafe/theme/colors.dart';
import 'package:smartsafe/Dashboard/services/firebase_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smartsafe/utils/error_message.dart';

class ContactModel {
  String id;
  String name;
  String phone;
  String relationship;
  String priority;

  ContactModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    required this.priority,
  });
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({Key? key}) : super(key: key);

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _selectedRelationship = "Family";
  String _selectedPriority = "Primary";
  ContactModel? _editingContact;

  /// Masks a phone number to show only the last 4 digits.
  /// e.g. "03118260476" → "*******0476"
  String _maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) return phone;
    final visible = digits.substring(digits.length - 4);
    final masked = '*' * (digits.length - 4);
    return '$masked$visible';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showContactDialog([ContactModel? contact]) {
    _editingContact = contact;
    if (contact != null) {
      _nameController.text = contact.name;
      _phoneController.text = contact.phone;
      _selectedRelationship = contact.relationship;
      _selectedPriority = contact.priority;
    } else {
      _nameController.clear();
      _phoneController.clear();
      _selectedRelationship = "Family";
      _selectedPriority = "Primary";
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: C.bg2,
              title: Text(contact == null ? "Add Trusted Contact" : "Edit Trusted Contact", style: TextStyle(color: C.textPrimary)),
              content: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(color: C.textPrimary),
                        decoration: const InputDecoration(labelText: "Name"),
                        validator: (value) => value == null || value.isEmpty ? "Please enter a name" : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _phoneController,
                        style: TextStyle(color: C.textPrimary),
                        decoration: const InputDecoration(labelText: "Phone Number"),
                        validator: (value) => value == null || value.isEmpty ? "Please enter a phone number" : null,
                      ),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        dropdownColor: C.bg2,
                        initialValue: _selectedRelationship,
                        decoration: const InputDecoration(labelText: "Relationship"),
                        items: ["Family", "Friend", "Neighbor", "Police", "Hospital"].map((val) {
                          return DropdownMenuItem(value: val, child: Text(val, style: TextStyle(color: C.textPrimary)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => _selectedRelationship = val);
                          }
                        },
                      ),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        dropdownColor: C.bg2,
                        initialValue: _selectedPriority,
                        decoration: const InputDecoration(labelText: "Priority"),
                        items: ["Primary", "Secondary"].map((val) {
                          return DropdownMenuItem(value: val, child: Text(val, style: TextStyle(color: C.textPrimary)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => _selectedPriority = val);
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
                        if (_editingContact == null) {
                          await FirebaseService.instance.contactsCollection.add({
                            'name': _nameController.text,
                            'phone': _phoneController.text,
                            'relationship': _selectedRelationship,
                            'priority': _selectedPriority,
                          });
                        } else {
                          await FirebaseService.instance.contactsCollection.doc(_editingContact!.id).update({
                            'name': _nameController.text,
                            'phone': _phoneController.text,
                            'relationship': _selectedRelationship,
                            'priority': _selectedPriority,
                          });
                        }
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(contact == null ? "Contact Added" : "Contact Updated")),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(friendlyErrorMessage(e))),
                        );
                      }
                    }
                  },
                  child: Text(contact == null ? "Add" : "Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteContact(ContactModel contact) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: C.bg2,
        title: Text("Delete Contact", style: TextStyle(color: C.textPrimary)),
        content: Text("Are you sure you want to delete ${contact.name}?", style: TextStyle(color: C.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: C.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.accent),
            onPressed: () async {
              try {
                await FirebaseService.instance.contactsCollection.doc(contact.id).delete();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Contact Deleted")),
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
            const PageHeaderBar(
              title: "User Emergency Contacts",
              subtitle: "Mobile app se add kiye gaye contacts — poora data",
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
                  stream: FirebaseService.instance.getEmergencyContactsStream(),
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
                          child: Text("No emergency contacts from app yet.", style: TextStyle(color: Colors.white70)),
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                      columnSpacing: dataTableColumnSpacing(context),
                      columns: const [
                        DataColumn(label: Text("App User")),
                        DataColumn(label: Text("Contact Name")),
                        DataColumn(label: Text("Phone")),
                        DataColumn(label: Text("Relationship")),
                        DataColumn(label: Text("SMS")),
                        DataColumn(label: Text("Push")),
                      ],
                      rows: docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final userLabel = data['userName']?.toString().isNotEmpty == true
                            ? data['userName'].toString()
                            : data['userEmail']?.toString() ?? data['userId']?.toString() ?? '—';
                        return DataRow(
                          cells: [
                            DataCell(Text(userLabel, style: TextStyle(color: C.accentLight, fontSize: 12))),
                            DataCell(Text(data['name']?.toString() ?? '—', style: TextStyle(color: C.textPrimary))),
                            DataCell(Text(_maskPhone(data['phone']?.toString() ?? '—'), style: TextStyle(color: C.textMuted))),
                            DataCell(Text(data['relationship']?.toString() ?? data['role']?.toString() ?? '—', style: TextStyle(color: C.textMuted))),
                            DataCell(Icon(
                              data['smsAlert'] != false ? Icons.check_circle : Icons.cancel,
                              color: data['smsAlert'] != false ? C.success : C.textMuted,
                              size: 18,
                            )),
                            DataCell(Icon(
                              data['pushAlert'] != false ? Icons.check_circle : Icons.cancel,
                              color: data['pushAlert'] != false ? C.success : C.textMuted,
                              size: 18,
                            )),
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
