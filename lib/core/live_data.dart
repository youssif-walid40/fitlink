import 'dart:async';

/// Wraps a live stream value with explicit loading / error states so every
/// StreamProvider in the app exposes the same shape to the UI.
class LiveData<T> {
  final T? data;
  final Object? error;
  final bool loading;

  const LiveData.loading([T? cached])
      : data = cached,
        error = null,
        loading = true;
  const LiveData.data(T value)
      : data = value,
        error = null,
        loading = false;
  const LiveData.error(Object e, [T? cached])
      : data = cached,
        error = e,
        loading = false;

  bool get hasData => data != null;
}

extension LiveStream<T> on Stream<T> {
  /// Converts data and errors into [LiveData] values so a StreamProvider never
  /// throws into the widget tree.
  Stream<LiveData<T>> asLive() => transform(
        StreamTransformer<T, LiveData<T>>.fromHandlers(
          handleData: (d, sink) => sink.add(LiveData.data(d)),
          handleError: (e, st, sink) => sink.add(LiveData.error(e)),
        ),
      );
}

/// Turns Firebase / network errors into short, human messages.
String friendlyError(Object? e) {
  final s = e?.toString() ?? 'Unknown error';
  if (s.contains('permission-denied')) return 'You do not have access to this content.';
  if (s.contains('unavailable') || s.contains('SocketException') || s.contains('network')) {
    return 'No connection. Check your internet and try again.';
  }
  if (s.contains('failed-precondition') && s.contains('index')) {
    return 'A Firestore index is still building. Try again in a minute.';
  }
  if (s.contains('wrong-password') || s.contains('invalid-credential')) {
    return 'Incorrect email or password.';
  }
  if (s.contains('user-not-found')) return 'No account found for that email.';
  if (s.contains('email-already-in-use')) return 'An account already exists for that email.';
  if (s.contains('too-many-requests')) return 'Too many attempts. Please wait and try again.';
  return s.replaceFirst('Exception: ', '');
}
