/// App-wide configuration and fixed option lists.
class AppConfig {
  AppConfig._();

  /// Base URL of the FitLink REST backend.
  /// Override at build time:  flutter run --dart-define=BACKEND_URL=https://api.example.com
  /// 10.0.2.2 is the Android emulator's alias for your computer's localhost.
  static const backendUrl =
      String.fromEnvironment('BACKEND_URL', defaultValue: 'http://10.0.2.2:8080');

  /// Images are stored by the backend and saved in Firestore as relative paths
  /// ("/files/..."). This turns them into full URLs for the current device.
  static String? mediaUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return url.startsWith('/') ? '$backendUrl$url' : url;
  }

  static const freeScanQuota = 2;
  static const freeProgressQuota = 1;

  // Cairo – used when GPS is unavailable and no last location is cached.
  static const defaultLat = 30.0444;
  static const defaultLng = 31.2357;

  static const facilities = [
    'Showers',
    'Lockers',
    'Parking',
    'Pool',
    'Sauna',
    'Women-only hours',
    'Open 24/7',
    'Open late',
    'Cardio zone',
    'Free weights',
    'Classes',
    'CrossFit area',
  ];

  static const specialties = [
    'Fat loss',
    'Strength',
    'Muscle gain',
    'Mobility',
    'Nutrition',
    'Powerlifting',
    'Calisthenics',
    'Rehab',
    'Endurance',
  ];

  static const goals = {
    'fat_loss': 'Fat loss',
    'muscle_gain': 'Muscle gain',
    'maintenance': 'Maintenance',
  };

  static const levels = ['Beginner', 'Intermediate', 'Advanced'];

  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static const premiumPlans = {
    'monthly': (label: 'Monthly', price: 99, period: 'month'),
    'yearly': (label: 'Yearly', price: 899, period: 'year'),
  };
}
