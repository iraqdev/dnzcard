import 'package:intl/intl.dart';

class Formatters {
  static final NumberFormat _iqd = NumberFormat('#,###', 'en');

  static String money(num value) {
    return '${_iqd.format(value)} د.ع';
  }

  static String date(DateTime value) {
    return DateFormat('yyyy/MM/dd - HH:mm', 'en').format(value);
  }

  static String shortDate(DateTime value) {
    return DateFormat('yyyy/MM/dd', 'en').format(value);
  }
}
