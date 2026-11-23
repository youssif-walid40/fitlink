import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/live_data.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../models/chat.dart';
import '../../models/coaching.dart';
import '../../providers/session_provider.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/coaching_repository.dart';
import '../../services/api_service.dart';
import '../../services/cache_service.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';
import '../coaching/coaching_widgets.dart';

/// Real-time one-to-one chat. Messages stream from Firestore; the unsent text
/// is kept as a draft in SharedPreferences.
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.chatId});
  final String chatId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ChatRepository>();
    return MultiProvider(
      providers: [
        StreamProvider<LiveData<List<ChatMessage>>>(
          initialData: const LiveData.loading(),
          create: (_) => repo.watchMessages(chatId).asLive(),
        ),
        StreamProvider<ChatThread?>(
          initialData: null,
          create: (_) => repo.watchThread(chatId),
          catchError: (_, __) => null,
        ),
      ],
      child: _ChatView(chatId: chatId),
    );
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView({required this.chatId});
  final String chatId;

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _input = TextEditingController();
  late final CacheService _cache = context.read<CacheService>();
  late final NotificationService _notifications = context.read<NotificationService>();
  Timer? _draftTimer;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _input.text = _cache.chatDraft(widget.chatId) ?? '';
    _input.addListener(() {
      _draftTimer?.cancel();
      _draftTimer = Timer(const Duration(milliseconds: 400), () => _cache.saveChatDraft(widget.chatId, _input.text));
      setState(() {});
    });
    _notifications.activeChatId = widget.chatId;
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _cache.saveChatDraft(widget.chatId, _input.text);
    if (_notifications.activeChatId == widget.chatId) _notifications.activeChatId = null;
    _input.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final uid = context.read<SessionProvider>().uid!;
    setState(() => _sending = true);
    try {
      await context.read<ChatRepository>().send(widget.chatId, senderId: uid, text: text);
      _input.clear();
      await _cache.saveChatDraft(widget.chatId, '');
      if (mounted) {
        context.read<ApiService>().notify(type: 'chat', refId: widget.chatId, preview: text);
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage(bool camera) async {
    final uid = context.read<SessionProvider>().uid!;
    final storage = context.read<StorageService>();
    final chats = context.read<ChatRepository>();
    final api = context.read<ApiService>();
    try {
      final file = await storage.pickImage(fromCamera: camera, maxWidth: 1280);
      if (file == null) return;
      setState(() => _sending = true);
      final url = await storage.uploadImage('chats/${widget.chatId}/${StorageService.uniqueName()}', file);
      await chats.send(widget.chatId, senderId: uid, type: MessageType.image, imageUrl: url);
      api.notify(type: 'chat', refId: widget.chatId, preview: '📷 Photo');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<SessionProvider>().uid!;
    final thread = context.watch<ChatThread?>();
    final live = context.watch<LiveData<List<ChatMessage>>>();
    final name = thread?.otherName(uid) ?? 'Chat';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => goBack(context)),
        titleSpacing: 0,
        title: Row(children: [
          UserAvatar(initials: initialsOf(name), url: thread?.otherPhoto(uid), radius: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17))),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: LiveView<List<ChatMessage>>(
            live: live,
            isEmpty: (m) => m.isEmpty,
            empty: const EmptyView(icon: Icons.waving_hand_outlined, title: 'Say hi 👋', message: 'Messages are private between you two.'),
            builder: (msgs) => ListView.builder(
              reverse: true,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final m = msgs[i];
                final showDate = i == msgs.length - 1 ||
                    !_sameDay(m.createdAt, msgs[i + 1].createdAt);
                return Column(children: [
                  if (showDate && m.createdAt != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(DateFormat.yMMMd().format(m.createdAt!),
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                  _Bubble(m: m, mine: m.senderId == uid),
                ]);
              },
            ),
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(children: [
              PopupMenuButton<bool>(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                onSelected: _sendImage,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: true, child: Text('Take photo')),
                  PopupMenuItem(value: false, child: Text('Choose from gallery')),
                ],
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Write a message', counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _sending || _input.text.trim().isEmpty ? null : _sendText,
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                  child: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Send'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  static bool _sameDay(DateTime? a, DateTime? b) =>
      a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m, required this.mine});
  final ChatMessage m;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxW = MediaQuery.sizeOf(context).width * 0.75;
    Widget content;
    switch (m.type) {
      case MessageType.image:
        content = ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(AppConfig.mediaUrl(m.imageUrl) ?? ''))),
            ),
            child: Image.network(AppConfig.mediaUrl(m.imageUrl) ?? '', width: 220, height: 220, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(width: 220, height: 120, child: Icon(Icons.broken_image))),
          ),
        );
      case MessageType.scan:
        content = InkWell(
          onTap: () => context.push('/scan/${m.payload['memberId']}/${m.payload['scanId']}'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: AppColors.lime, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.monitor_weight_outlined, size: 18, color: AppColors.ink),
                SizedBox(width: 6),
                Text('InBody scan attached', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              ]),
              if ('${m.payload['headline'] ?? ''}'.isNotEmpty)
                Text('${m.payload['headline']}', style: const TextStyle(color: AppColors.ink, fontSize: 13)),
              const Text('Tap to view', style: TextStyle(color: AppColors.ink, fontSize: 12)),
            ]),
          ),
        );
      case MessageType.proposal:
        content = _ProposalBubble(m: m);
      case MessageType.text:
        content = Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: mine ? AppColors.ink : scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: mine ? null : Border.all(color: scheme.outline),
          ),
          child: Text(m.text, style: TextStyle(color: mine ? Colors.white : scheme.onSurface, height: 1.35)),
        );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: m.type == MessageType.proposal ? maxW * 1.2 : maxW),
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                content,
                if (m.createdAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                    child: Text(DateFormat.jm().format(m.createdAt!),
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Proposal card inside the chat. The member can accept or counter directly
/// while the coaching is still in the "proposed" state.
class _ProposalBubble extends StatelessWidget {
  const _ProposalBubble({required this.m});
  final ChatMessage m;

  @override
  Widget build(BuildContext context) {
    final p = m.payload;
    final coachingId = '${p['coachingId'] ?? ''}';
    final user = context.watch<SessionProvider>().user!;
    final coaching = context.watch<LiveData<List<Coaching>>>().data?.where((c) => c.id == coachingId).firstOrNull;
    final proposal = PlanProposal(
      title: '${p['title'] ?? 'Plan'}',
      durationWeeks: (p['durationWeeks'] as num?)?.toInt() ?? 0,
      sessionsPerWeek: (p['sessionsPerWeek'] as num?)?.toInt() ?? 0,
      price: (p['price'] as num?)?.toInt() ?? 0,
      nutrition: p['nutrition'] == true ? const NutritionTargets(calories: 0, proteinG: 0, waterL: 0) : null,
    );
    final canAnswer = coaching != null &&
        coaching.status == CoachingStatus.proposed &&
        coaching.memberId == user.uid &&
        coaching.proposal?.title == proposal.title;

    return ProposalCard(
      proposal: proposal,
      actions: canAnswer
          ? Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.push('/coaching/$coachingId/counter'),
                  child: const Text('Counter'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    try {
                      await context.read<CoachingRepository>().acceptProposal(coachingId, user);
                      if (context.mounted) {
                        context.read<ApiService>().notify(type: 'coaching', refId: coachingId);
                        showSnack(context, 'Plan accepted 💪');
                      }
                    } catch (e) {
                      if (context.mounted) showSnack(context, friendlyError(e), error: true);
                    }
                  },
                  child: const Text('Accept'),
                ),
              ),
            ])
          : SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.push('/coaching/$coachingId'),
                child: Text(coaching == null ? 'View' : coaching.status.label),
              ),
            ),
    );
  }
}
