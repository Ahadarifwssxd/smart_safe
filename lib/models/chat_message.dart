import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderPhone;
  final String receiverPhone;
  final String message;
  final DateTime timestamp;
  final bool isOfflineSms;
  final bool isRead;
  final String type; // 'text', 'image'
  final String? imageUrl;

  ChatMessage({
    required this.id,
    this.conversationId = '',
    required this.senderId,
    required this.senderPhone,
    required this.receiverPhone,
    required this.message,
    required this.timestamp,
    this.isOfflineSms = false,
    this.isRead = false,
    this.type = 'text',
    this.imageUrl,
  });

  factory ChatMessage.fromFirestore(String id, Map<String, dynamic> data) {
    final ts = data['timestamp'];
    DateTime time = DateTime.now();
    if (ts is Timestamp) {
      time = ts.toDate();
    } else if (ts is String) {
      time = DateTime.tryParse(ts) ?? DateTime.now();
    }
    return ChatMessage(
      id: id,
      conversationId: data['conversationId']?.toString() ?? '',
      senderId: data['senderId']?.toString() ?? '',
      senderPhone: data['senderPhone']?.toString() ?? '',
      receiverPhone: data['receiverPhone']?.toString() ?? '',
      message: data['message']?.toString() ?? '',
      timestamp: time,
      isOfflineSms: data['isOfflineSms'] == true,
      isRead: data['isRead'] == true,
      type: data['type']?.toString() ?? 'text',
      imageUrl: data['imageUrl']?.toString(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderPhone': senderPhone,
      'receiverPhone': receiverPhone,
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
      'isOfflineSms': isOfflineSms,
      'isRead': isRead,
      'type': type,
      if (imageUrl != null) 'imageUrl': imageUrl,
    };
  }
}
