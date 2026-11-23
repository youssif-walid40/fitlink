import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/coaching.dart';
import '../../providers/session_provider.dart';
import '../constants.dart';
import '../live_data.dart';
import '../theme.dart';

// ---------------------------------------------------------------------------
// Loading / empty / error states
// ---------------------------------------------------------------------------

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!, textAlign: TextAlign.center),
          ],
        ]),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(color: AppColors.limeSoft, shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: AppColors.ink),
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: muted)),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ]),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyView(
        icon: Icons.cloud_off_rounded,
        title: 'Something went wrong',
        message: friendlyError(error),
        action: onRetry == null
            ? null
            : OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      );
}

/// Renders a [LiveData] value with uniform loading / error / empty handling.
class LiveView<T> extends StatelessWidget {
  const LiveView({
    super.key,
    required this.live,
    required this.builder,
    this.isEmpty,
    this.empty,
    this.onRetry,
  });

  final LiveData<T> live;
  final Widget Function(T data) builder;
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (live.data == null) {
      if (live.error != null) return ErrorView(error: live.error, onRetry: onRetry);
      return const LoadingView();
    }
    final data = live.data as T;
    if (isEmpty?.call(data) ?? false) {
      return empty ?? const EmptyView(icon: Icons.inbox_outlined, title: 'Nothing here yet');
    }
    return Column(children: [
      if (live.error != null)
        MaterialBanner(
          content: Text('Showing saved data. ${friendlyError(live.error)}'),
          actions: [if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')) else const SizedBox()],
        ),
      Expanded(child: builder(data)),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.initials, this.url, this.radius = 24});
  final String initials;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final resolved = AppConfig.mediaUrl(url);
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.ink,
      foregroundImage: resolved != null ? NetworkImage(resolved) : null,
      child: Text(
        initials,
        style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w700, fontSize: radius * 0.62),
      ),
    );
  }
}

String initialsOf(String name) {
  final parts = name.replaceFirst('Coach ', '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.highlighted = false, this.color});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool highlighted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: highlighted ? scheme.onSurface : scheme.outline, width: highlighted ? 1.4 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// The dark card with lime heading used for summaries and active plans.
class DarkCard extends StatelessWidget {
  const DarkCard({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child),
          ),
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Row(children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (action != null) action!,
        ]),
      );
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.textColor, this.icon});
  final String text;
  final Color? color;
  final Color? textColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color ?? scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: textColor ?? scheme.onSurface), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: textColor ?? scheme.onSurface)),
      ]),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.sub});
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          if (sub != null) Text(sub!, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final CoachingStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      CoachingStatus.active => (AppColors.lime, AppColors.ink),
      CoachingStatus.completed => (AppColors.success, Colors.white),
      CoachingStatus.declined || CoachingStatus.cancelled => (AppColors.danger.withValues(alpha: 0.15), AppColors.danger),
      CoachingStatus.proposed || CoachingStatus.countered => (AppColors.warning.withValues(alpha: 0.18), const Color(0xFF8A6200)),
      _ => (Theme.of(context).colorScheme.surfaceContainerHighest, Theme.of(context).colorScheme.onSurface),
    };
    return Tag(status.label.toUpperCase(), color: bg, textColor: fg);
  }
}

class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.size = 16});
  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final icon = rating >= i + 1
              ? Icons.star_rounded
              : rating > i
                  ? Icons.star_half_rounded
                  : Icons.star_outline_rounded;
          return Icon(icon, size: size, color: AppColors.warning);
        }),
      );
}

/// Network image with a soft placeholder (used for gym photos, transformations).
class NetImage extends StatelessWidget {
  const NetImage({super.key, this.url, this.height, this.width, this.icon = Icons.fitness_center, this.label, this.radius = 12});
  final String? url;
  final double? height;
  final double? width;
  final IconData icon;
  final String? label;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      height: height,
      width: width,
      color: const Color(0xFFDCE3D0),
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.ink.withValues(alpha: 0.45)),
    );
    final resolved = AppConfig.mediaUrl(url);
    final img = resolved == null
        ? placeholder
        : Image.network(
            resolved,
            height: height,
            width: width,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder,
            loadingBuilder: (c, child, p) => p == null ? child : Container(height: height, width: width, color: scheme.surfaceContainerHighest),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(children: [
        img,
        if (label != null)
          Positioned(
            left: 8,
            bottom: 8,
            child: Tag(label!, color: AppColors.ink.withValues(alpha: 0.8), textColor: Colors.white),
          ),
      ]),
    );
  }
}

class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon, this.outlined = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ]);
    return outlined
        ? OutlinedButton(onPressed: busy ? null : onPressed, child: child)
        : FilledButton(onPressed: busy ? null : onPressed, child: child);
  }
}

/// App bar action that opens the signed-in user's profile.
class ProfileAction extends StatelessWidget {
  const ProfileAction({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionProvider>().user;
    if (user == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => context.push('/profile'),
        child: UserAvatar(initials: user.initials, url: user.photoUrl, radius: 18),
      ),
    );
  }
}

class Disclaimer extends StatelessWidget {
  const Disclaimer({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'General fitness guidance generated by AI. This is not medical advice or a diagnosis. '
              'Talk to a doctor about any health concerns.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : null,
    ));
}

Future<bool> confirm(BuildContext context, {required String title, required String message, String ok = 'Confirm', bool danger = false}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Back navigation that also works when a screen was opened from a
/// notification (no previous route): falls back to /home.
void goBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/home');
  }
}

String egp(num v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return 'EGP $buf';
}

String fmtNum(double v, {int digits = 1}) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(digits);
