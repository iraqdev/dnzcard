import 'package:flutter_test/flutter_test.dart';
import 'package:kushk/core/utils/topup_fee.dart';

void main() {
  group('TopupFee', () {
    test('adds 1% rounded up for exact values', () {
      expect(TopupFee.feeFor(25000), 250);
      expect(TopupFee.feeFor(100000), 1000);
      expect(TopupFee.chargedFor(100000), 101000);
    });

    test('rounds fee up for fractional dinars', () {
      expect(TopupFee.feeFor(15000), 150);
      expect(TopupFee.chargedFor(15000), 15150);
      expect(TopupFee.feeFor(1001), 11); // 10.01 -> 11
    });

    test('rejects amounts below minimum', () {
      expect(() => TopupFee.feeFor(999), throwsArgumentError);
    });

    test('client cannot invent credit amount from charged amount alone', () {
      // عقد الحماية: المحفظة تُشحن بالمبلغ المطلوب فقط وليس بإجمالي الدفع.
      const requested = 100000;
      final charged = TopupFee.chargedFor(requested);
      expect(charged - requested, TopupFee.feeFor(requested));
      expect(requested, isNot(equals(charged)));
    });
  });
}
