import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local, offline-first cache of the user's emergency contacts and identity.
///
/// SIM calls and SIM SMS work with NO internet (they use the cellular voice /
/// SMS network, not data). The SOS dispatch, however, used to read the contact
/// list from Firestore — so with no connection it could stall or find nothing
/// and send nothing. This cache is written whenever contacts are seen online
/// (the contacts/home screens, and every SOS), and read back when a real SOS
/// is fired offline — guaranteeing the SIM channels can always reach someone.
class OfflineSosCache {
  OfflineSosCache._();

  static const _contactsKey = 'sos_contacts_cache_v1';
  static const _senderNameKey = 'sos_sender_name_v1';
  static const _senderPhoneKey = 'sos_sender_phone_v1';

  /// Persist the slim fields the offline dispatch needs (phone/name/flags).
  static Future<void> saveContacts(List<Map<String, dynamic>> contacts) async {
    try {
      final slim = contacts
          .map((c) => {
                'id': c['id']?.toString() ?? '',
                'phone': c['phone']?.toString() ?? '',
                'name': c['name']?.toString() ?? 'Contact',
                'smsAlert': c['smsAlert'] != false,
                'callAlert': c['callAlert'] != false,
                'email': c['email']?.toString() ?? '',
              })
          .where((c) => (c['phone'] as String).trim().isNotEmpty)
          .toList();
      if (slim.isEmpty) return; // never overwrite a good cache with nothing
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_contactsKey, jsonEncode(slim));
    } catch (e) {
      debugPrint('[OfflineSosCache] saveContacts failed: $e');
    }
  }

  /// The last-known emergency contacts, usable with no internet. Empty if none
  /// were ever cached (e.g. a brand-new account that has only ever been offline).
  static Future<List<Map<String, dynamic>>> loadContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_contactsKey);
      if (raw == null || raw.isEmpty) return [];
      return (jsonDecode(raw) as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } catch (e) {
      debugPrint('[OfflineSosCache] loadContacts failed: $e');
      return [];
    }
  }

  static Future<void> saveSender({String? name, String? phone}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (name != null && name.trim().isNotEmpty) {
        await prefs.setString(_senderNameKey, name.trim());
      }
      if (phone != null && phone.trim().isNotEmpty) {
        await prefs.setString(_senderPhoneKey, phone.trim());
      }
    } catch (e) {
      debugPrint('[OfflineSosCache] saveSender failed: $e');
    }
  }

  static Future<String?> senderName() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_senderNameKey);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> senderPhone() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_senderPhoneKey);
    } catch (_) {
      return null;
    }
  }
}
