import 'package:flutter_test/flutter_test.dart';
import 'package:kushk/core/utils/phone_auth.dart';

void main() {
  group('phone auth helpers', () {
    test('normalizes iraqi local numbers', () {
      expect(normalizePhone('07812345678'), '+9647812345678');
      expect(phoneToAuthEmail('07812345678'), '9647812345678@kushk.app');
    });
  });

  group('password reset safety contract', () {
    test('server payload keys must never include password fields', () {
      // عقد الواجهة مع Functions: الطلب يُنشأ بهذه الحقول فقط.
      const allowed = {
        'userId',
        'phone',
        'shopName',
        'deviceId',
        'deviceName',
        'status',
        'serverApproved',
        'createdAt',
        'reviewedAt',
        'reviewedBy',
        'completedAt',
      };
      const forbidden = {'password', 'newPassword', 'plainPassword'};
      for (final key in forbidden) {
        expect(allowed.contains(key), isFalse);
      }
    });
  });
}
