import 'package:shared_preferences/shared_preferences.dart';

/// قياس ورق الطابعة الحرارية.
enum PaperSizeMm {
  mm58(58, 384, 192),
  mm80(80, 576, 288);

  const PaperSizeMm(this.mm, this.dots, this.logicalWidth);

  final int mm;
  /// عرض الطباعة بالنقاط (203dpi تقريبًا).
  final int dots;
  /// عرض ويدجت الإيصال قبل الالتقاط مع pixelRatio=2.
  final double logicalWidth;

  String get label => '${mm}mm';

  static PaperSizeMm fromMm(int? value) {
    if (value == 80) return PaperSizeMm.mm80;
    return PaperSizeMm.mm58;
  }

  static PaperSizeMm fromStorage(String? raw) {
    final n = int.tryParse(raw ?? '');
    return fromMm(n);
  }
}

class PaperSizePrefs {
  static const _key = 'kushk_paper_size_mm';

  static Future<PaperSizeMm> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PaperSizeMm.fromStorage(prefs.getString(_key));
  }

  static Future<void> save(PaperSizeMm size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, size.mm.toString());
  }
}
