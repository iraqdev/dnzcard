/// تحويل رقم الهاتف إلى بريد داخلي لـ Firebase Auth (بدون إظهاره للمستخدم).
String phoneToAuthEmail(String phone) {
  var normalized = phone.trim().replaceAll(RegExp(r'[\s\-()]'), '');
  if (normalized.startsWith('+')) {
    normalized = normalized.substring(1);
  }
  if (normalized.startsWith('00')) {
    normalized = normalized.substring(2);
  }
  if (normalized.startsWith('0')) {
    normalized = '964${normalized.substring(1)}';
  }
  return '$normalized@kushk.app';
}

/// استخراج رقم الهاتف من البريد الداخلي `964…@kushk.app`.
String? authEmailToPhone(String? email) {
  if (email == null || email.isEmpty) return null;
  final local = email.trim().split('@').first;
  if (local.isEmpty) return null;
  if (local.startsWith('+')) return local;
  return '+$local';
}

String normalizePhone(String phone) {
  var normalized = phone.trim().replaceAll(RegExp(r'[\s\-()]'), '');
  if (normalized.startsWith('+')) return normalized;
  if (normalized.startsWith('00')) return '+${normalized.substring(2)}';
  if (normalized.startsWith('0')) return '+964${normalized.substring(1)}';
  return normalized;
}
