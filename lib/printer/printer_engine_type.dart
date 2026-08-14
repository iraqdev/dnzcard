/// أنواع الطابعات المدعومة — يختارها المستخدم أو يضبطها الاكتشاف التلقائي.
enum PrinterEngineType {
  /// محرك كشك الأصلي (Centerm / USB / BT / شبكة / بائعون).
  kushkNative,
  switchPos,
  sunmi,
  senraise,
  bluetoothV1,
  bluetoothV2,
  /// طابعات الجيب Mini / iPrint / SC03h (بروتوكول BLE خاص).
  bluetoothMini,
  k9,
  usb,
  network,
  androidPrint,
}

extension PrinterEngineTypeLabels on PrinterEngineType {
  String get label => switch (this) {
        PrinterEngineType.kushkNative => 'DNZ card تلقائي (موصى به)',
        PrinterEngineType.switchPos => 'Switch Pos',
        PrinterEngineType.sunmi => 'Sunmi',
        PrinterEngineType.senraise => 'Senraise',
        PrinterEngineType.bluetoothV1 => 'Bluetooth V1',
        PrinterEngineType.bluetoothV2 => 'Bluetooth V2',
        PrinterEngineType.bluetoothMini => 'Bluetooth Mini',
        PrinterEngineType.k9 => 'K9 / iPos',
        PrinterEngineType.usb => 'USB',
        PrinterEngineType.network => 'شبكة (Wi-Fi / Ethernet)',
        PrinterEngineType.androidPrint => 'نظام طباعة أندرويد',
      };

  String get description => switch (this) {
        PrinterEngineType.kushkNative =>
          'اكتشاف تلقائي لطابعة الجهاز (Centerm وغيرها)',
        PrinterEngineType.switchPos =>
          'أجهزة كاشير متعددة الماركات (PAX / Gertec / …)',
        PrinterEngineType.sunmi => 'طابعة Sunmi المدمجة',
        PrinterEngineType.senraise => 'طابعة Senraise / Rovoo H10 المدمجة',
        PrinterEngineType.bluetoothV1 =>
          'طابعة Bluetooth خارجية — اختر الجهاز يدوياً',
        PrinterEngineType.bluetoothV2 =>
          'طابعة Bluetooth خارجية — اكتشاف تلقائي',
        PrinterEngineType.bluetoothMini =>
          'طابعة جيب Mini / iPrint / SC03h — اختر الجهاز ثم اطبع',
        PrinterEngineType.k9 => 'طابعة Centerm K9 المدمجة (iPos)',
        PrinterEngineType.usb =>
          'طابعة حرارية موصولة بكيبل USB — أي ماركة ESC/POS',
        PrinterEngineType.network =>
          'طابعة شبكة على نفس الشبكة (منفذ 9100) — أدخل عنوان IP',
        PrinterEngineType.androidPrint =>
          'أي طابعة مثبّتة في نظام أندرويد (خدمات الطباعة)',
      };

  bool get needsBluetooth =>
      this == PrinterEngineType.bluetoothV1 ||
      this == PrinterEngineType.bluetoothV2 ||
      this == PrinterEngineType.bluetoothMini;

  bool get usesKushkNativeChannel => this == PrinterEngineType.kushkNative;

  static PrinterEngineType fromId(String? id) {
    if (id == null || id.isEmpty) return PrinterEngineType.kushkNative;
    return PrinterEngineType.values.firstWhere(
      (e) => e.name == id,
      orElse: () => PrinterEngineType.kushkNative,
    );
  }
}
