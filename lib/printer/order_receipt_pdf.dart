import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/catalog_models.dart';
import '../models/order_model.dart';
import 'receipt_paper_profile.dart';
import 'receipt_qr_payload.dart';

/// بناء إيصال PDF لكشك مع QR حسب شركة الاتصالات.
abstract final class OrderReceiptPdf {
  static const _developerPhone = '+9647878783591';

  static pw.Font? _baseFont;
  static pw.Font? _boldFont;

  static Future<pw.ThemeData> _arabicTheme() async {
    _baseFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Regular.ttf'),
    );
    _boldFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Bold.ttf'),
    );
    return pw.ThemeData.withFont(
      base: _baseFont!,
      bold: _boldFont!,
    );
  }

  static String _formatDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year  $hour:$minute';
  }

  static pw.Widget _boxedText({
    required String text,
    required double fontSize,
    required pw.TextDirection direction,
    bool bold = true,
  }) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(width: 1.2, color: PdfColors.black),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: PdfColors.black,
        ),
        textAlign: pw.TextAlign.center,
        textDirection: direction,
      ),
    );
  }

  static pw.Widget _developerBox({
    required pw.TextDirection rtl,
    required ReceiptPaperProfile profile,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(width: 1, color: PdfColors.black),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'المطور',
            style: pw.TextStyle(
              fontSize: profile.developerTitleFont,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
            textAlign: pw.TextAlign.center,
            textDirection: rtl,
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'dnzteam.online',
            style: pw.TextStyle(
              fontSize: profile.developerSiteFont,
              color: PdfColors.black,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            _developerPhone,
            style: pw.TextStyle(
              fontSize: profile.developerPhoneFont,
              color: PdfColors.black,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  static Future<Uint8List> buildForOrder({
    required OrderModel order,
    required String shopName,
    required ReceiptPaperProfile profile,
    int? printNumber,
  }) async {
    final theme = await _arabicTheme();
    final doc = pw.Document(theme: theme);
    const rtl = pw.TextDirection.rtl;
    final name = shopName.trim().isEmpty ? 'DNZ card' : shopName.trim();
    final company =
        order.companyName.trim().isEmpty ? '—' : order.companyName.trim();
    final category =
        order.productName.trim().isEmpty ? '—' : order.productName.trim();
    final number = printNumber ?? order.nextPrintNumber;
    final items = order.cardItems.isNotEmpty
        ? order.cardItems
        : const [CardItem(code: '—', serialNumber: '')];

    for (final item in items) {
      final code = item.code;
      final serial = item.serialNumber.trim();
      final qrData = ReceiptQrPayload.forCompany(
        companyName: order.companyName,
        pinCode: code,
      );

      doc.addPage(
        pw.Page(
          pageTheme: pw.PageTheme(
            pageFormat: profile.pageFormat,
            margin: profile.pageMargin,
            theme: theme,
            buildBackground: (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Container(color: PdfColors.white),
            ),
          ),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                '======= DNZ card =======',
                style: pw.TextStyle(
                  fontSize: profile.shopNameFont,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
                textAlign: pw.TextAlign.center,
                textDirection: rtl,
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                name,
                style: pw.TextStyle(
                  fontSize: profile.shopNameFont,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
                textAlign: pw.TextAlign.center,
                textDirection: rtl,
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'time: ${_formatDateTime(order.createdAt)}',
                style: pw.TextStyle(
                  fontSize: profile.dateFont,
                  color: PdfColors.black,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'serial: ${serial.isEmpty ? '—' : serial}',
                style: pw.TextStyle(
                  fontSize: profile.dateFont,
                  color: PdfColors.black,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 8),
              _boxedText(
                text: company,
                fontSize: profile.productFont,
                direction: rtl,
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                category,
                style: pw.TextStyle(
                  fontSize: profile.productFont,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
                textAlign: pw.TextAlign.center,
                textDirection: rtl,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'PIN CODE',
                style: pw.TextStyle(
                  fontSize: profile.codeLabelFont,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 4),
              _boxedText(
                text: code,
                fontSize: profile.codeFont,
                direction: pw.TextDirection.ltr,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                '$number',
                style: pw.TextStyle(
                  fontSize: profile.shopNameFont + 2,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'كيو ار كود',
                style: pw.TextStyle(
                  fontSize: profile.codeLabelFont,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
                textAlign: pw.TextAlign.center,
                textDirection: rtl,
              ),
              if (ReceiptQrPayload.rechargeHintForCompany(order.companyName)
                  case final hint?) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  hint,
                  style: pw.TextStyle(
                    fontSize: profile.dateFont,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                  textAlign: pw.TextAlign.center,
                  textDirection: rtl,
                ),
              ],
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: qrData.isEmpty ? '—' : qrData,
                  width: profile.qrSize,
                  height: profile.qrSize,
                  color: PdfColors.black,
                  backgroundColor: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 8),
              _developerBox(rtl: rtl, profile: profile),
              pw.SizedBox(height: 8),
              pw.Text(
                'DNZ card يرحب بالجميع',
                style: pw.TextStyle(
                  fontSize: profile.codeLabelFont,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
                textAlign: pw.TextAlign.center,
                textDirection: rtl,
              ),
              pw.SizedBox(height: profile.bottomSpace),
            ],
          ),
        ),
      );
    }

    return doc.save();
  }

  static Future<Uint8List> buildTest({
    required ReceiptPaperProfile profile,
  }) {
    return buildForOrder(
      order: OrderModel(
        id: 'test',
        shopId: '',
        productId: '',
        productName: '5000',
        companyName: 'اسياسيل',
        quantity: 1,
        unitPrice: 0,
        total: 0,
        cardItems: const [
          CardItem(code: '12345678901234', serialNumber: 'TEST-000001'),
        ],
        paymentMethod: 'wallet',
        status: 'completed',
        createdAt: DateTime.now(),
        printCount: 0,
      ),
      shopName: 'اختبار الطابعة',
      profile: profile,
      printNumber: 1,
    );
  }
}
