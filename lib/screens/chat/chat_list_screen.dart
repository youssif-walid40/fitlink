import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/live_data.dart';
import '../../core/widgets/common.dart';
import '../../models/chat.dart';
import '../../providers/session_provider.dart';
import '../coaching/coaching_widgets.dart' show timeAgo;

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<SessionProvider>().uid!;
    final live = context.watch<LiveData<List<ChatThread>>>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Chat'), actions: const [ProfileAction()]),
      body: LiveView<List<ChatThread>>(
        live: live,
        isEmpty: (t) => t.isEmpty,
        empty: const EmptyView(
          icon: Icons.chat_bubble_outline,
          title: 'No conversations yet',
          message: 'Message a trainer from their profile, or open the chat from a coaching request.',
        ),
        builder: (threads) => ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: threads.length,
          separatorBuilder: (_, __) => const Divider(indent: 76),
          itemBuilder: (_, i) {
            final t = threads[i];
            final unread = t.lastSenderId.isNotEmpty && t.lastSenderId != uid;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              onTap: () => context.push('/chat/${t.id}'),
              leading: UserAvatar(initials: initialsOf(t.otherName(uid)), url: t.otherPhoto(uid), radius: 24),
              title: Text(t.otherName(uid), style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
              subtitle: Text(
                '${t.lastSenderId == uid ? 'You: ' : ''}${t.lastMessage}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: unread ? null : muted, fontWeight: unread ? FontWeight.w600 : null),
              ),
              trailing: Text(timeAgo(t.updatedAt), style: TextStyle(fontSize: 12, color: muted)),
            );
          },
        ),
      ),
    );
  }
}
