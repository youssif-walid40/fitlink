import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../repositories/user_repository.dart';

/// Firebase Cloud Messaging integration.
///
/// * Foreground: shows an in-app banner (SnackBar) with an "Open" action.
/// * Background: the OS shows the notification; tapping fires onMessageOpenedApp.
/// * Terminated: getInitialMessage() returns the tapped message on launch.
/// Every push carries data.route (e.g. /chat/abc or /coaching/xyz) which is
/// opened with go_router.
class NotificationService {
  NotificationService(this._users);

  final UserRepository _users;
  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  GoRouter? _router;
  GlobalKey<ScaffoldMessengerState>? _messengerKey;
  String? _uid;
  String? _token;
  String? _pendingRoute;
  bool _initialized = false;

  /// The chat currently on screen – its message pushes are not shown as banners.
  String? activeChatId;

  void attach(GoRouter router, GlobalKey<ScaffoldMessengerState> messengerKey) {
    _router = router;
    _messengerKey = messengerKey;
  }

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;
    await _fm.requestPermission(alert: true, badge: true, sound: true);
    // iOS: we render our own foreground banner, so don't show the system one.
    await _fm.setForegroundNotificationPresentationOptions(alert: false, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => open(m.data['route'] as String?));
    final initial = await _fm.getInitialMessage();
    if (initial != null) _pendingRoute = initial.data['route'] as String?;

    _fm.onTokenRefresh.listen((t) {
      _token = t;
      if (_uid != null) _users.addFcmToken(_uid!, t);
    });
  }

  /// Called once the signed-in user's profile has loaded.
  Future<void> onSignedIn(String uid) async {
    _uid = uid;
    try {
      await _init();
      _token = await _fm.getToken();
      if (_token != null) await _users.addFcmToken(uid, _token!);
    } catch (e) {
      debugPrint('FCM setup failed: $e');
    }
    if (_pendingRoute != null) {
      final r = _pendingRoute!;
      _pendingRoute = null;
      // Let the router settle on /home first so Back returns there.
      Future.delayed(const Duration(milliseconds: 400), () {
        _router?.go('/home');
        _router?.push(r);
      });
    }
  }

  Future<void> onSignOut() async {
    final uid = _uid;
    _uid = null;
    if (uid != null && _token != null) {
      try {
        await _users.removeFcmToken(uid, _token!);
      } catch (_) {}
    }
  }

  void open(String? route) {
    if (route == null || route.isEmpty) return;
    if (_uid == null || _router == null) {
      _pendingRoute = route;
      return;
    }
    _router!.push(route);
  }

  void _onForeground(RemoteMessage m) {
    final chatId = m.data['chatId'];
    if (chatId != null && chatId == activeChatId) return;
    final title = m.notification?.title ?? m.data['title'] ?? 'FitLink';
    final body = m.notification?.body ?? m.data['body'] ?? '';
    final route = m.data['route'] as String?;
    _messengerKey?.currentState?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$title', style: const TextStyle(fontWeight: FontWeight.w700)),
            if ('$body'.isNotEmpty) Text('$body', maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        action: route == null ? null : SnackBarAction(label: 'Open', onPressed: () => open(route)),
      ),
    );
  }
}
