/// Form validators. Each returns null when valid, or an error message.
class Validators {
  Validators._();

  static final _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  static String? required(String? v, [String field = 'This field']) =>
      (v == null || v.trim().isEmpty) ? '$field is required' : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    return _email.hasMatch(v.trim()) ? null : 'Enter a valid email';
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'\d').hasMatch(v)) return 'Include at least one number';
    return null;
  }

  static String? name(String? v) {
    if (v == null || v.trim().length < 2) return 'Enter your full name';
    if (v.trim().length > 50) return 'Name is too long';
    return null;
  }

  static String? phone(String? v) {
    if (v == null || v.trim().isEmpty) return null; // optional
    return RegExp(r'^\+?\d{8,15}$').hasMatch(v.trim()) ? null : 'Enter a valid phone number';
  }

  /// Validates a number within [min, max]. Empty is allowed when [optional].
  static String? number(String? v,
      {double min = 0, double max = double.infinity, bool optional = false, String field = 'Value'}) {
    if (v == null || v.trim().isEmpty) return optional ? null : '$field is required';
    final n = double.tryParse(v.trim());
    if (n == null) return 'Enter a number';
    if (n < min || n > max) {
      return '$field must be between ${_fmt(min)} and ${_fmt(max)}';
    }
    return null;
  }

  static String _fmt(double d) => d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}
