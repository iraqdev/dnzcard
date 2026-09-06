/// حساب رسوم شحن المحفظة حسب وسيلة الدفع.
class TopupFee {
  /// ماستركارد / فيزا (DNZ).
  static const cardRate = 0.01;

  /// زين كاش.
  static const zainCashRate = 0.007;

  /// تحويل سوبر كي (تحويل يدوي — بدون عمولة في التطبيق).
  static const superKeyRate = 0.0;

  /// الحد الأدنى لمبلغ الإيداع عبر سوبر كي.
  static const superKeyMinAmount = 5000000;

  /// للتوافق مع المسار القديم (بطاقة).
  static const rate = cardRate;

  static const minAmount = 1000;

  static int feeFor(int requestedAmount, {double rate = cardRate}) {
    if (requestedAmount < minAmount) {
      throw ArgumentError('أدخل مبلغاً صحيحاً بالدينار ($minAmount فأكثر)');
    }
    return (requestedAmount * rate).ceil();
  }

  static int chargedFor(int requestedAmount, {double rate = cardRate}) =>
      requestedAmount + feeFor(requestedAmount, rate: rate);
}
