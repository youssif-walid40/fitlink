import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat.dart';

class ChatRepository {
  ChatRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _chats => _db.collection('chats');

  /// One deterministic thread per pair of users.
  static String chatIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('_');
  }

  /// Creates the thread if needed (merge keeps existing messages/fields).
  Future<String> openThread({
    required String meId,
    required String meName,
    String? mePhoto,
    required String otherId,
    required String otherName,
    String? otherPhoto,
  }) async {
    final id = chatIdFor(meId, otherId);
    await _chats.doc(id).set({
      'participants': [meId, otherId]..sort(),
      'names': {meId: meName, otherId: otherName},
      'photos': {meId: mePhoto ?? '', otherId: otherPhoto ?? ''},
    }, SetOptions(merge: true));
    return id;
  }

  Stream<List<ChatThread>> watchThreads(String uid) => _chats
      .where('participants', arrayContains: uid)
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(ChatThread.fromDoc).toList());

  Stream<ChatThread?> watchThread(String chatId) =>
      _chats.doc(chatId).snapshots().map((d) => d.exists ? ChatThread.fromDoc(d) : null);

  /// Newest first (the chat list is rendered reversed).
  Stream<List<ChatMessage>> watchMessages(String chatId, {int limit = 100}) => _chats
      .doc(chatId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(ChatMessage.fromDoc).toList());

  Future<void> send(
    String chatId, {
    required String senderId,
    MessageType type = MessageType.text,
    String text = '',
    String? imageUrl,
    Map<String, dynamic> payload = const {},
  }) async {
    final batch = _db.batch();
    final msg = _chats.doc(chatId).collection('messages').doc();
    batch.set(msg, {
      'senderId': senderId,
      'type': type.name,
      'text': text.trim(),
      'imageUrl': imageUrl,
      'payload': payload,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_chats.doc(chatId), {
      'lastMessage': previewFor(type, text),
      'lastSenderId': senderId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  static String previewFor(MessageType type, String text) => switch (type) {
        MessageType.text => text.trim(),
        MessageType.image => '📷 Photo',
        MessageType.scan => '📊 InBody scan shared',
        MessageType.proposal => '📋 Plan proposal',
      };
}
