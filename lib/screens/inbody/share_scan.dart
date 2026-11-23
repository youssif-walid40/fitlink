import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/live_data.dart';
import '../../core/widgets/common.dart';
import '../../models/chat.dart';
import '../../models/coaching.dart';
import '../../models/scan.dart';
import '../../providers/scan_history_provider.dart';
import '../../providers/session_provider.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/coaching_repository.dart';
import '../../repositories/scan_repository.dart';
import '../../services/api_service.dart';

String scanHeadline(Scan s) => [
      if (s['percentBodyFat'] != null) 'Body fat ${fmtNum(s['percentBodyFat']!)}%',
      if (s['skeletalMuscleMass'] != null) 'Muscle ${fmtNum(s['skeletalMuscleMass']!)} kg',
    ].join(' · ');

/// User-controlled sharing: grants one PT read access to one scan, records it on
/// the coaching and posts it in the chat.
Future<void> shareScanWithTrainer(BuildContext context, Scan scan) async {
  final user = context.read<SessionProvider>().user!;
  const shareable = {CoachingStatus.accepted, CoachingStatus.proposed, CoachingStatus.countered, CoachingStatus.active};
  final coachings = (context.read<LiveData<List<Coaching>>>().data ?? const <Coaching>[])
      .where((c) => c.memberId == user.uid && shareable.contains(c.status))
      .toList();

  if (coachings.isEmpty) {
    showSnack(context, 'Hire a trainer first – then you can share scans with them.');
    return;
  }

  Coaching? target = coachings.length == 1 ? coachings.first : null;
  target ??= await showModalBottomSheet<Coaching>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Share with which trainer?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
        for (final co in coachings)
          ListTile(
            leading: UserAvatar(initials: initialsOf(co.ptName), url: co.ptPhoto, radius: 18),
            title: Text(co.ptName),
            subtitle: Text(co.status.label),
            onTap: () => Navigator.pop(c, co),
          ),
      ]),
    ),
  );
  if (target == null || !context.mounted) return;

  final ok = await confirm(
    context,
    title: 'Share with ${target.ptName}?',
    message: 'Your coach will be able to see this scan\'s values and AI summary. Other scans stay private.',
    ok: 'Share',
  );
  if (!ok || !context.mounted) return;

  try {
    final chats = context.read<ChatRepository>();
    await context.read<ScanRepository>().shareWith(user.uid, scan.id, target.ptId);
    await context.read<CoachingRepository>().addSharedScan(target.id, scan.id);
    final chatId = await chats.openThread(
      meId: user.uid,
      meName: user.name,
      mePhoto: user.photoUrl,
      otherId: target.ptId,
      otherName: target.ptName,
      otherPhoto: target.ptPhoto,
    );
    await chats.send(chatId, senderId: user.uid, type: MessageType.scan, payload: {
      'memberId': user.uid,
      'scanId': scan.id,
      'headline': scanHeadline(scan),
    });
    if (!context.mounted) return;
    context.read<ScanHistoryProvider>().markShared(scan.id, target.ptId);
    context.read<ApiService>().notify(type: 'chat', refId: chatId, preview: 'Shared an InBody scan');
    showSnack(context, 'Scan shared with ${target.ptName}');
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyError(e), error: true);
  }
}

/// Shown when the backend answers 402 (free quota used up).
Future<void> showPremiumPrompt(BuildContext context, String message, VoidCallback openPremium) => showDialog(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.workspace_premium_outlined, size: 36),
        title: const Text('Upgrade to Premium'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Not now')),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              openPremium();
            },
            child: const Text('See plans'),
          ),
        ],
      ),
    );
