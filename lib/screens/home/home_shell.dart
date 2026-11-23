import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/live_data.dart';
import '../../models/app_user.dart';
import '../../models/chat.dart';
import '../../models/coaching.dart';
import '../../providers/session_provider.dart';
import '../admin/admin_screen.dart';
import '../chat/chat_list_screen.dart';
import '../coaching/clients_screen.dart';
import '../coaching/plans_screen.dart';
import '../gyms/gyms_screen.dart';
import '../inbody/inbody_screen.dart';
import '../owner/owner_dashboard_screen.dart';
import '../trainers/trainers_screen.dart';

class _TabSpec {
  final String key;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() build;
  const _TabSpec(this.key, this.label, this.icon, this.selectedIcon, this.build);
}

/// Bottom-navigation home. The tabs depend on the user's role; the selected
/// tab can be set from a route: /home?tab=chat
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.tab});
  final String? tab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _built = <String, Widget>{};

  List<_TabSpec> _tabsFor(UserRole role) {
    final gyms = _TabSpec('gyms', 'Gyms', Icons.place_outlined, Icons.place, () => const GymsScreen());
    final trainers =
        _TabSpec('trainers', 'Trainers', Icons.sports_gymnastics_outlined, Icons.sports_gymnastics, () => const TrainersScreen());
    final chat = _TabSpec('chat', 'Chat', Icons.chat_bubble_outline, Icons.chat_bubble, () => const ChatListScreen());
    return switch (role) {
      UserRole.member => [
          gyms,
          trainers,
          chat,
          _TabSpec('plans', 'Plans', Icons.event_note_outlined, Icons.event_note, () => const PlansScreen()),
          _TabSpec('inbody', 'InBody', Icons.monitor_weight_outlined, Icons.monitor_weight, () => const InBodyScreen()),
        ],
      UserRole.pt => [
          _TabSpec('clients', 'Clients', Icons.groups_outlined, Icons.groups, () => const ClientsScreen()),
          chat,
          gyms,
        ],
      UserRole.owner => [
          _TabSpec('dashboard', 'My gym', Icons.storefront_outlined, Icons.storefront, () => const OwnerDashboardScreen()),
          gyms,
        ],
      UserRole.admin => [
          _TabSpec('admin', 'Review', Icons.verified_user_outlined, Icons.verified_user, () => const AdminScreen(embedded: true)),
          gyms,
          trainers,
        ],
    };
  }

  void _syncTab(List<_TabSpec> tabs) {
    final i = tabs.indexWhere((t) => t.key == widget.tab);
    if (i >= 0) _index = i;
  }

  @override
  void didUpdateWidget(covariant HomeShell old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) _pendingSync = true;
  }

  bool _pendingSync = true;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionProvider>().user;
    if (user == null) return const Scaffold(body: SizedBox.shrink());
    final tabs = _tabsFor(user.role);
    if (_pendingSync) {
      _syncTab(tabs);
      _pendingSync = false;
    }
    if (_index >= tabs.length) _index = 0;

    // Badges: open requests needing my action / chats where the other person spoke last.
    final coachings = context.watch<LiveData<List<Coaching>>>().data ?? const [];
    final threads = context.watch<LiveData<List<ChatThread>>>().data ?? const [];
    final needsAction = coachings.where((c) => _needsMyAction(c, user)).length;
    final unreadChats = threads.where((t) => t.lastSenderId.isNotEmpty && t.lastSenderId != user.uid).length;

    // Build tabs lazily and keep them alive in an IndexedStack.
    final children = [
      for (var i = 0; i < tabs.length; i++)
        i == _index || _built.containsKey(tabs[i].key)
            ? (_built[tabs[i].key] ??= tabs[i].build())
            : const SizedBox.shrink(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: children),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: _badge(t, Icon(t.icon), needsAction, unreadChats),
              selectedIcon: _badge(t, Icon(t.selectedIcon), needsAction, unreadChats),
              label: t.label,
            ),
        ],
      ),
    );
  }

  Widget _badge(_TabSpec t, Widget icon, int needsAction, int unread) {
    final count = switch (t.key) {
      'plans' || 'clients' => needsAction,
      'chat' => unread,
      _ => 0,
    };
    return count == 0 ? icon : Badge(label: Text('$count'), child: icon);
  }

  static bool _needsMyAction(Coaching c, AppUser u) {
    if (u.uid == c.ptId) {
      return c.status == CoachingStatus.requested ||
          c.status == CoachingStatus.accepted ||
          c.status == CoachingStatus.countered;
    }
    if (u.uid == c.memberId) {
      return c.status == CoachingStatus.proposed || (c.status == CoachingStatus.completed && !c.reviewed);
    }
    return false;
  }
}
