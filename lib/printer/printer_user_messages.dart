/// رسائل عربية واضحة للمستخدم.
abstract final class PrinterUserMessages {
  static const printSuccess = 'تم إرسال الإيصال للطابعة';
  static const unrecognized = 'لم يتم التعرف على الطابعة';

  static String forPrintError(Object error) {
    final text = error.toString();
    final lower = text.toLowerCase();
    final code = _extractCode(text);

    if (lower.contains('sunmi_printer_unavailable') ||
        lower.contains('sunmi_not_available')) {
      return _withCode(
        'طابعة Sunmi غير متاحة. تأكد أن الجهاز يدعم الطباعة المدمجة.',
        code,
      );
    }
    if (lower.contains('switch_pos_init_failed') ||
        lower.contains('switch_pos_print_failed')) {
      return _withCode(
        'تعذر الاتصال بطابعة Switch Pos. تأكد من نوع الطابعة في الإعدادات.',
        code,
      );
    }
    if (lower.contains('builtin_printer_not_available') ||
        lower.contains('senraise_not_available')) {
      return _withCode(
        'لم تُعثر على خدمة طابعة مدمجة. لجهاز Rovoo/H10 اختر «Senraise».',
        code,
      );
    }
    if (lower.contains('bluetooth_device_not_selected')) {
      return _withCode(
        'اختر طابعة Bluetooth من إعدادات الطابعة أولاً.',
        code,
      );
    }
    if (lower.contains('mini_ble_device_not_selected')) {
      return _withCode(
        'اختر طابعة Mini من إعدادات الطابعة أولاً.',
        code,
      );
    }
    if (lower.contains('mini_ble_write_char_missing')) {
      return _withCode(
        'تعذر العثور على قناة الطباعة لطابعة Mini. تأكد أنها من نوع iPrint/SC03h.',
        code,
      );
    }
    if (lower.contains('usb_printer_not_found')) {
      return _withCode(
        'لم تُعثر على طابعة USB. تأكد من توصيل الكيبل وتشغيل الطابعة.',
        code,
      );
    }
    if (lower.contains('usb_permission_denied') ||
        lower.contains('usb_permission_failed')) {
      return _withCode(
        'لم تُمنح صلاحية طابعة USB. اسمح بالوصول من إعدادات الطابعة.',
        code,
      );
    }
    if (lower.contains('network_printer_not_configured')) {
      return _withCode(
        'أدخل عنوان IP لطابعة الشبكة من إعدادات الطابعة أولاً.',
        code,
      );
    }
    if (lower.contains('network_print_failed')) {
      return _withCode(
        'تعذر الاتصال بطابعة الشبكة. تأكد أنها على نفس الشبكة وأن IP صحيح.',
        code,
      );
    }
    if (lower.contains('ipos_not_available') ||
        lower.contains('ipos_bind_timeout')) {
      return _withCode(
        'خدمة iPos/K9 غير متاحة على هذا الجهاز.',
        code,
      );
    }
    if (lower.contains('esc_pos_device_missing') ||
        lower.contains('esc_pos_connect_failed')) {
      return _withCode(
        'تعذر الاتصال بطابعة Bluetooth. تأكد من الاقتران والتشغيل.',
        code,
      );
    }
    if (lower.contains('print_android_only')) {
      return _withCode('الطباعة متاحة على أجهزة Android فقط.', code);
    }
    return _withCode('تعذرت الطباعة. أعد المحاولة أو راجع إعدادات الطابعة.', code);
  }

  static String _extractCode(String text) {
    final match = RegExp(r'[A-Z][A-Z0-9_]{4,}').firstMatch(text);
    return match?.group(0) ?? '';
  }

  static String _withCode(String message, String code) {
    if (code.isEmpty) return message;
    return '$message ($code)';
  }
}
