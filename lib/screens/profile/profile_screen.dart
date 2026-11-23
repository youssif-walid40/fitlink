import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../models/app_user.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final user = session.user;
    if (user == null) return const Scaffold(body: LoadingView());
    final settings = context.watch<SettingsProvider>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => goBack(context)),
        title: const Text('Profile'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/profile/edit'),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Center(
          child: Column(children: [
            UserAvatar(initials: user.initials, url: user.photoUrl, radius: 46),
            const SizedBox(height: 12),
            Text(user.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text(user.email, style: TextStyle(color: muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              Tag(user.role.label.toUpperCase()),
              if (user.isPremium) const Tag('PREMIUM', icon: Icons.workspace_premium, color: AppColors.lime, textColor: AppColors.ink),
            ]),
          ]),
        ),
        const SizedBox(height: 20),
        if (user.isMember) ...[
          AppCard(
            child: Column(children: [
              _Row(icon: Icons.flag_outlined, label: 'Goal', value: AppConfig.goals[user.goal] ?? user.goal),
              const Divider(),
              _Row(
                icon: Icons.storefront_outlined,
                label: 'Gym',
                value: user.gymName == null ? 'Not a member yet' : '${user.gymName} · ${user.gymTier}',
                onTap: user.gymId == null ? null : () => context.push('/gyms/${user.gymId}'),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          user.isPremium
              ? AppCard(
                  child: _Row(
                    icon: Icons.workspace_premium,
                    label: 'Premium',
                    value: user.premiumUntil == null ? 'Active' : 'Until ${DateFormat.yMMMd().format(user.premiumUntil!)}',
                  ),
                )
              : DarkCard(
                  onTap: () => context.push('/premium'),
                  child: const Row(children: [
                    Icon(Icons.workspace_premium_outlined, color: AppColors.lime),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Go Premium', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('Unlimited InBody analysis and progress reports',
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ]),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.lime),
                  ]),
                ),
        ],
        if (user.isPt)
          AppCard(
            child: Column(children: [
              _Row(icon: Icons.badge_outlined, label: 'Trainer profile', value: 'Bio, prices, transformations', onTap: () => context.push('/pt/edit')),
              const Divider(),
              _Row(icon: Icons.visibility_outlined, label: 'Public view', value: 'See what members see', onTap: () => context.push('/trainers/${user.uid}')),
            ]),
          ),
        if (user.isOwner)
          AppCard(
            child: _Row(icon: Icons.storefront_outlined, label: 'Gym listing', value: 'Edit tiers, photos, policies', onTap: () => context.push('/owner/gym')),
          ),
        const SectionHeader('Settings'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Theme', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (s) => settings.setThemeMode(s.first),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
          onPressed: () async {
            if (await confirm(context, title: 'Log out?', message: 'You will need to sign in again.', ok: 'Log out')) {
              await session.signOut();
            }
          },
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'FitLink v1.0 · Member since ${user.createdAt == null ? '-' : DateFormat.yMMM().format(user.createdAt!)}',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value, this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(icon, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(value, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            if (onTap != null) const Icon(Icons.chevron_right),
          ]),
        ),
      );
}
