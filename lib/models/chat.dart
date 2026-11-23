import 'package:cloud_firestore/cloud_firestore.dart';

import 'parse.dart';

class ChatThread {
  final String id;
  final List<String> participants;
  final Map<String, String> names;
  final Map<String, String> photos;
  final String lastMessage;
  final String lastSenderId;
  final DateTime? updatedAt;

  const ChatThread({
    required this.id,
    required this.participants,
    this.names = const {},
    this.photos = const {},
    this.lastMessage = '',
    this.lastSenderId = '',
    this.updatedAt,
  });

  String otherId(String me) => participants.firstWhere((p) => p != me, orElse: () => me);
  String otherName(String me) => names[otherId(me)] ?? 'User';
  String? otherPhoto(String me) {
    final p = photos[otherId(me)];
    return (p == null || p.isEmpty) ? null : p;
  }

  factory ChatThread.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return ChatThread(
      id: doc.id,
      participants: asStringList(d['participants']),
      names: asMap(d['names']).map((k, v) => MapEntry(k, '$v')),
      photos: asMap(d['photos']).map((k, v) => MapEntry(k, '${v ?? ''}')),
      lastMessage: d['lastMessage'] ?? '',
      lastSenderId: d['lastSenderId'] ?? '',
      updatedAt: asDate(d['updatedAt']),
    );
  }
}

enum MessageType { text, image, scan, proposal }

class ChatMessage {
  final String id;
  final String senderId;
  final MessageType type;
  final String text;
  final String? imageUrl;
  final Map<String, dynamic> payload;
  final DateTime? createdAt;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.type,
    this.text = '',
    this.imageUrl,
    this.payload = const {},
    this.createdAt,
  });

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return ChatMessage(
      id: doc.id,
      senderId: d['senderId'] ?? '',
      type: MessageType.values.firstWhere((t) => t.name == d['type'], orElse: () => MessageType.text),
      text: d['text'] ?? '',
      imageUrl: d['imageUrl'],
      payload: asMap(d['payload']),
      // Pending server timestamps are null locally; show them as "now".
      createdAt: asDate(d['createdAt']) ?? DateTime.now(),
    );
  }
}
