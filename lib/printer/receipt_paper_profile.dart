import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// مقاسات الإيصال حسب عرض ورق الطابعة (58mm أو 80mm).
class ReceiptPaperProfile {
  const ReceiptPaperProfile({
    required this.paperWidthMm,
    required this.pageFormat,
    required this.printWidthPx,
    required this.pageMargin,
    required this.shopNameFont,
    required this.brandingFont,
    required this.dateFont,
    required this.productFont,
    required this.codeLabelFont,
    required this.codeFont,
    required this.developerTitleFont,
    required this.developerSiteFont,
    required this.developerPhoneFont,
    required this.qrSize,
    required this.bottomSpace,
    required this.stackQrVertically,
  });

  final int paperWidthMm;
  final PdfPageFormat pageFormat;
  final int printWidthPx;
  final pw.EdgeInsets pageMargin;
  final double shopNameFont;
  final double brandingFont;
  final double dateFont;
  final double productFont;
  final double codeLabelFont;
  final double codeFont;
  final double developerTitleFont;
  final double developerSiteFont;
  final double developerPhoneFont;
  final double qrSize;
  final double bottomSpace;
  final bool stackQrVertically;

  bool get isNarrow => paperWidthMm <= 58;

  double get rasterDpi {
    final pageWidthInches = pageFormat.width / PdfPageFormat.inch;
    final naturalPx = pageWidthInches * 203;
    if (naturalPx <= 0) return 203;
    return 203 * printWidthPx / naturalPx;
  }

  /// ارتفاع محدود للـ PDF — الارتفاع اللانهائي يسبب ورقة سوداء عند الـ raster.
  static PdfPageFormat _roll(double widthMm, double heightMm) => PdfPageFormat(
        widthMm * PdfPageFormat.mm,
        heightMm * PdfPageFormat.mm,
        marginAll: 0,
      );

  static final ReceiptPaperProfile mm58 = ReceiptPaperProfile(
    paperWidthMm: 58,
    pageFormat: _roll(57, 280),
    printWidthPx: 384,
    pageMargin: const pw.EdgeInsets.fromLTRB(10, 6, 10, 10),
    shopNameFont: 10,
    brandingFont: 9,
    dateFont: 8,
    productFont: 10,
    codeLabelFont: 9,
    codeFont: 14,
    developerTitleFont: 8,
    developerSiteFont: 8,
    developerPhoneFont: 9,
    qrSize: 68,
    bottomSpace: 14,
    stackQrVertically: true,
  );

  static final ReceiptPaperProfile mm80 = ReceiptPaperProfile(
    paperWidthMm: 80,
    pageFormat: _roll(80, 300),
    printWidthPx: 576,
    pageMargin: const pw.EdgeInsets.fromLTRB(8, 6, 8, 16),
    shopNameFont: 12,
    brandingFont: 10,
    dateFont: 10,
    productFont: 11,
    codeLabelFont: 10,
    codeFont: 17,
    developerTitleFont: 9,
    developerSiteFont: 9,
    developerPhoneFont: 10,
    qrSize: 92,
    bottomSpace: 20,
    stackQrVertically: false,
  );

  static ReceiptPaperProfile forPaperWidthMm(int mm) =>
      mm <= 58 ? mm58 : mm80;

  static ReceiptPaperProfile resolve({
    int? paperOverrideMm,
    int defaultMm = 58,
  }) {
    final mm = paperOverrideMm ?? defaultMm;
    return forPaperWidthMm(mm);
  }
}
