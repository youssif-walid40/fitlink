import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/live_data.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'models/chat.dart';
import 'models/coaching.dart';
import 'models/gym.dart';
import 'models/pt_profile.dart';
import 'providers/gym_filter_provider.dart';
import 'providers/scan_history_provider.dart';
import 'providers/session_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/trainer_filter_provider.dart';
import 'repositories/admin_repository.dart';
import 'repositories/chat_repository.dart';
import 'repositories/coaching_repository.dart';
import 'repositories/gym_repository.dart';
import 'repositories/pt_repository.dart';
import 'repositories/scan_repository.dart';
import 'repositories/user_repository.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/cache_service.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';
import 'services/ocr_service.dart';
import 'services/storage_service.dart';

class FitLinkApp extends StatefulWidget {
  const FitLinkApp({super.key, required this.cache});
  final CacheService cache;

  @override
  State<FitLinkApp> createState() => _FitLinkAppState();
}

class _FitLinkAppState extends State<FitLinkApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final UserRepository _users = UserRepository();
  late final AuthService _auth = AuthService();
  late final NotificationService _notifications = NotificationService(_users);
  late final SessionProvider _session = SessionProvider(_auth, _users, _notifications);
  late final GoRouter _router = buildRouter(_session);

  @override
  void initState() {
    super.initState();
    _notifications.attach(_router, _messengerKey);
  }

  @override
  Widget build(BuildContext context) {
    final cache = widget.cache;
    return MultiProvider(
      providers: [
        // Services and repositories (plain Provider – they don't change).
        Provider.value(value: cache),
        Provider.value(value: _auth),
        Provider.value(value: _users),
        Provider.value(value: _notifications),
        Provider(create: (_) => ApiService()),
        Provider(create: (c) => StorageService(c.read<ApiService>())),
        Provider(create: (_) => OcrService()),
        Provider(create: (_) => GymRepository(cache)),
        Provider(create: (_) => PtRepository(cache)),
        Provider(create: (_) => CoachingRepository()),
        Provider(create: (_) => ChatRepository()),
        Provider(create: (_) => ScanRepository()),
        Provider(create: (_) => AdminRepository()),
        // App state (ChangeNotifier providers).
        ChangeNotifierProvider.value(value: _session),
        ChangeNotifierProvider(create: (_) => SettingsProvider(cache)),
        ChangeNotifierProvider(create: (_) => GymFilterProvider(LocationService(cache))),
        ChangeNotifierProvider(create: (_) => TrainerFilterProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) => MaterialApp.router(
          title: 'FitLink',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: settings.themeMode,
          scaffoldMessengerKey: _messengerKey,
          routerConfig: _router,
          builder: (context, child) => SignedInScope(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}

/// Live data streams that exist only while someone is signed in.
/// They sit above the Navigator, so every screen (including ones opened from
/// a notification) can read them. Keyed by uid so they reset on account switch.
class SignedInScope extends StatelessWidget {
  const SignedInScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final uid = context.select<SessionProvider, String?>((s) => s.user?.uid);
    if (uid == null) {
      // Signed out: expose empty values so screens that are still animating
      // out never hit a ProviderNotFoundException.
      return MultiProvider(
        providers: [
          Provider<LiveData<List<Gym>>>.value(value: const LiveData.loading()),
          Provider<LiveData<List<PtProfile>>>.value(value: const LiveData.loading()),
          Provider<LiveData<List<Coaching>>>.value(value: const LiveData.loading()),
          Provider<LiveData<List<ChatThread>>>.value(value: const LiveData.loading()),
        ],
        child: child,
      );
    }
    final cache = context.read<CacheService>();
    return KeyedSubtree(
      key: ValueKey(uid),
      child: MultiProvider(
        providers: [
          StreamProvider<LiveData<List<Gym>>>(
            initialData: LiveData.loading(cache.cachedGyms.isEmpty ? null : cache.cachedGyms),
            create: (c) => c.read<GymRepository>().watchGyms().asLive(),
          ),
          StreamProvider<LiveData<List<PtProfile>>>(
            initialData: LiveData.loading(cache.cachedPts.isEmpty ? null : cache.cachedPts),
            create: (c) => c.read<PtRepository>().watchPts().asLive(),
          ),
          StreamProvider<LiveData<List<Coaching>>>(
            initialData: const LiveData.loading(),
            create: (c) => c.read<CoachingRepository>().watchForUser(uid).asLive(),
          ),
          StreamProvider<LiveData<List<ChatThread>>>(
            initialData: const LiveData.loading(),
            create: (c) => c.read<ChatRepository>().watchThreads(uid).asLive(),
          ),
          ChangeNotifierProvider(create: (c) => ScanHistoryProvider(c.read<ScanRepository>(), uid)),
        ],
        child: child,
      ),
    );
  }
}
