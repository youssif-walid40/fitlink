import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../repositories/user_repository.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

/// Holds who is signed in and their live profile. go_router listens to this
/// (refreshListenable) so protected routes re-evaluate on every auth change.
class SessionProvider extends ChangeNotifier {
  SessionProvider(this._auth, this._users, this._notifications) {
    _authSub = _auth.authChanges().listen(_onAuth, onError: (_) {
      initializing = false;
      notifyListeners();
    });
  }

  final AuthService _auth;
  final UserRepository _users;
  final NotificationService _notifications;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppUser?>? _userSub;

  bool initializing = true;
  User? firebaseUser;
  AppUser? user;
  Object? profileError;
  String? _notifiedUid;

  bool get isSignedIn => firebaseUser != null;
  String? get uid => firebaseUser?.uid;

  void _onAuth(User? u) {
    firebaseUser = u;
    _userSub?.cancel();
    profileError = null;
    if (u == null) {
      user = null;
      initializing = false;
      _notifiedUid = null;
      notifyListeners();
      return;
    }
    _userSub = _users.watchUser(u.uid).listen(
      (profile) {
        user = profile;
        initializing = false;
        notifyListeners();
        if (profile != null && _notifiedUid != profile.uid) {
          _notifiedUid = profile.uid;
          _notifications.onSignedIn(profile.uid);
        }
      },
      onError: (e) {
        profileError = e;
        initializing = false;
        notifyListeners();
      },
    );
  }

  Future<void> signOut() async {
    await _notifications.onSignOut();
    await _auth.logout();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }
}
