import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/app_user.dart';
import '../models/scan.dart';
import '../providers/session_provider.dart';
import '../screens/admin/admin_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/coaching/coaching_detail_screen.dart';
import '../screens/coaching/counter_offer_screen.dart';
import '../screens/coaching/proposal_editor_screen.dart';
import '../screens/coaching/review_screen.dart';
import '../screens/gyms/gym_detail_screen.dart';
import '../screens/home/home_shell.dart';
import '../screens/inbody/progress_screen.dart';
import '../screens/inbody/scan_capture_screen.dart';
import '../screens/inbody/scan_confirm_screen.dart';
import '../screens/inbody/scan_result_screen.dart';
import '../screens/owner/gym_editor_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/premium_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/pt/pt_profile_editor_screen.dart';
import '../screens/trainers/request_pt_screen.dart';
import '../screens/trainers/trainer_detail_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Structured routing with path parameters and protected routes.
/// Redirect rules:
///   * not signed in            -> /login
///   * signed in, profile loading -> /splash
///   * role-restricted prefixes -> /home if the role does not match
GoRouter buildRouter(SessionProvider session) => GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/splash',
      refreshListenable: session,
      redirect: (context, state) {
        final loc = state.matchedLocation;
        final onAuthPage = loc == '/login' || loc == '/register';

        if (session.initializing) return loc == '/splash' ? null : '/splash';
        if (!session.isSignedIn) return onAuthPage ? null : '/login';
        if (session.user == null) return loc == '/splash' ? null : '/splash';
        if (onAuthPage || loc == '/splash') return '/home';

        final role = session.user!.role;
        String? guard(String prefix, Set<UserRole> allowed) =>
            loc.startsWith(prefix) && !allowed.contains(role) ? '/home' : null;

        return guard('/owner', {UserRole.owner}) ??
            guard('/admin', {UserRole.admin}) ??
            guard('/inbody', {UserRole.member}) ??
            guard('/pt', {UserRole.pt}) ??
            (loc.endsWith('/propose') && role != UserRole.pt ? '/home' : null) ??
            ((loc.endsWith('/counter') || loc.endsWith('/review') || loc.endsWith('/request')) &&
                    role != UserRole.member
                ? '/home'
                : null);
      },
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
        GoRoute(
          path: '/home',
          builder: (_, s) => HomeShell(tab: s.uri.queryParameters['tab']),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, __) => const ProfileScreen(),
          routes: [
            GoRoute(path: 'edit', builder: (_, __) => const EditProfileScreen()),
          ],
        ),
        GoRoute(path: '/premium', builder: (_, __) => const PremiumScreen()),
        GoRoute(
          path: '/gyms/:gymId',
          builder: (_, s) => GymDetailScreen(gymId: s.pathParameters['gymId']!),
        ),
        GoRoute(
          path: '/trainers/:ptId',
          builder: (_, s) => TrainerDetailScreen(ptId: s.pathParameters['ptId']!),
          routes: [
            GoRoute(
              path: 'request',
              builder: (_, s) => RequestPtScreen(ptId: s.pathParameters['ptId']!),
            ),
          ],
        ),
        GoRoute(
          path: '/coaching/:id',
          builder: (_, s) => CoachingDetailScreen(coachingId: s.pathParameters['id']!),
          routes: [
            GoRoute(path: 'propose', builder: (_, s) => ProposalEditorScreen(coachingId: s.pathParameters['id']!)),
            GoRoute(path: 'counter', builder: (_, s) => CounterOfferScreen(coachingId: s.pathParameters['id']!)),
            GoRoute(path: 'review', builder: (_, s) => ReviewScreen(coachingId: s.pathParameters['id']!)),
          ],
        ),
        GoRoute(
          path: '/chat/:chatId',
          builder: (_, s) => ChatScreen(chatId: s.pathParameters['chatId']!),
        ),
        GoRoute(path: '/inbody/new', builder: (_, __) => const ScanCaptureScreen()),
        GoRoute(
          path: '/inbody/confirm',
          redirect: (_, s) => s.extra is ScanDraft ? null : '/inbody/new',
          builder: (_, s) => ScanConfirmScreen(draft: s.extra! as ScanDraft),
        ),
        GoRoute(path: '/inbody/progress', builder: (_, __) => const ProgressScreen()),
        GoRoute(
          path: '/scan/:memberId/:scanId',
          builder: (_, s) => ScanResultScreen(
            memberId: s.pathParameters['memberId']!,
            scanId: s.pathParameters['scanId']!,
          ),
        ),
        GoRoute(path: '/pt/edit', builder: (_, __) => const PtProfileEditorScreen()),
        GoRoute(path: '/owner/gym', builder: (_, __) => const GymEditorScreen()),
        GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
      ],
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Not found')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('No page at ${state.uri.path}'),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => context.go('/home'), child: const Text('Go home')),
          ]),
        ),
      ),
    );
