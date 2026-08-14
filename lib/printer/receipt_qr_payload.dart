/// محتوى QR حسب شركة الاتصالات.
abstract final class ReceiptQrPayload {
  /// اسياسيل → tel:*133*PIN%23
  /// زين العراق → tel:*101*PIN%23
  /// كورك → tel:*221*PIN%23
  /// غير ذلك → PIN فقط
  ///
  /// نستخدم `tel:` مع ترميز `#` إلى `%23` حتى يفتح قارئ QR تطبيق الاتصال.
  static String forCompany({
    required String companyName,
    required String pinCode,
  }) {
    final pin = pinCode.trim();
    if (pin.isEmpty || pin == '—') return pin;

    final prefix = ussdPrefixForCompany(companyName);
    if (prefix == null) return pin;
    return _telUssd('$prefix$pin');
  }

  /// نص توضيحي فوق الـ QR لآسيا / زين / كورك فقط، وإلا `null`.
  static String? rechargeHintForCompany(String companyName) {
    final prefix = ussdPrefixForCompany(companyName);
    if (prefix == null) return null;
    // مثال: لتعبئة الرصيد اضغط *133* وبعدها الرمز وبعدها #
    return 'لتعبئة الرصيد اضغط $prefix وبعدها الرمز وبعدها #';
  }

  /// بادئة USSD مع النجمة الأخيرة، مثل `*133*` — أو null إن لم تكن شركة شحن محلي.
  static String? ussdPrefixForCompany(String companyName) {
    final key = companyName.trim().toLowerCase();
    if (_isAsiacell(key)) return '*133*';
    if (_isZain(key)) return '*101*';
    if (_isKorek(key)) return '*221*';
    return null;
  }

  /// `tel:*CODE*PIN%23` — الـ `#` يجب أن يكون `%23` داخل رابط tel.
  static String _telUssd(String ussdWithoutHash) => 'tel:$ussdWithoutHash%23';

  static bool _isAsiacell(String name) {
    final compact = name.replaceAll(RegExp(r'\s+'), '');
    return compact.contains('اسياسيل') ||
        compact.contains('آسياسيل') ||
        name.contains('asia') ||
        name.contains('asiacell');
  }

  static bool _isZain(String name) {
    return name.contains('زين') || name.contains('zain');
  }

  static bool _isKorek(String name) {
    return name.contains('كورك') || name.contains('korek');
  }
}
