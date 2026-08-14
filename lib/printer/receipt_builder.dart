import '../core/utils/formatters.dart';
import '../models/order_model.dart';
import 'receipt_qr_payload.dart';

class ReceiptBuilder {
  static const brandLabel = 'DNZTEAM';

  static List<String> forOrder(
    OrderModel order, {
    String shopName = 'DNZ card',
    int? printNumber,
  }) {
    final name = shopName.trim().isEmpty ? 'DNZ card' : shopName.trim();
    final number = printNumber ?? order.nextPrintNumber;
    final lines = <String>[
      '======= DNZ card =======',
      name,
    ];

    for (final item in order.cardItems) {
      final hint =
          ReceiptQrPayload.rechargeHintForCompany(order.companyName);
      lines.addAll([
        'time: ${Formatters.date(order.createdAt)}',
        'serial: ${item.serialNumber.isEmpty ? '—' : item.serialNumber}',
        order.companyName.isEmpty ? '—' : order.companyName,
        order.productName,
        'PIN CODE',
        item.code,
        '$number',
        'كيو ار كود',
        if (hint != null) hint,
        'QR: ${ReceiptQrPayload.forCompany(companyName: order.companyName, pinCode: item.code)}',
      ]);
    }

    lines.addAll([
      '',
      'DNZ card يرحب بالجميع',
    ]);
    return lines;
  }
}
