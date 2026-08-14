import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/order_model.dart';
import '../../printer/receipt_qr_payload.dart';

/// إيصال موحّد يظهر عند «إظهار» ويطابق شكل الطباعة قدر الإمكان.
class CardReceiptView extends StatelessWidget {
  const CardReceiptView({
    super.key,
    required this.order,
    required this.shopName,
    this.compact = false,
    this.compactWidth = 288,
    this.printNumber,
  });

  final OrderModel order;
  final String shopName;
  final bool compact;
  /// عرض الإيصال عند الطباعة (يُضبط حسب 58mm / 80mm).
  final double compactWidth;
  /// رقم الطباعة المعروض؛ إن لم يُمرَّر يُستخدم العدد الحالي أو التالي.
  final int? printNumber;

  /// عامل تصغير الخط: الأحجام الأساسية مصممة لعرض 288 (ورق 80mm).
  double get _scale {
    if (!compact) return 1.0;
    return (compactWidth / 288).clamp(0.6, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final name = shopName.trim().isEmpty ? 'DNZ card' : shopName.trim();
    final company =
        order.companyName.trim().isEmpty ? '—' : order.companyName.trim();
    final category =
        order.productName.trim().isEmpty ? '—' : order.productName.trim();
    final number = printNumber ??
        (order.printCount > 0 ? order.printCount : order.nextPrintNumber);
    final s = _scale;
    final padH = compact ? (compactWidth < 220 ? 6.0 : 12.0) : 8.0;

    return Container(
      width: compact ? compactWidth : null,
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: padH,
        vertical: compact ? 12 : 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '======= DNZ card =======',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18 * s, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 10 * s),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15 * s, fontWeight: FontWeight.w700),
          ),
          for (final item in order.cardItems) ...[
            SizedBox(height: 10 * s),
            Text(
              'time: ${Formatters.date(order.createdAt)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12 * s),
            ),
            SizedBox(height: 4 * s),
            Text(
              'serial: ${item.serialNumber.isEmpty ? '—' : item.serialNumber}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12 * s),
            ),
            SizedBox(height: 10 * s),
            _Box(
              child: Text(
                company,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15 * s, fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(height: 8 * s),
            Text(
              category,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15 * s, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10 * s),
            Text(
              'PIN CODE',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6 * s),
            _Box(
              child: Text(
                item.code,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20 * s,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1 * s,
                ),
              ),
            ),
            SizedBox(height: 10 * s),
            Text(
              '$number',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18 * s, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8 * s),
            Text(
              'كيو ار كود',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13 * s, fontWeight: FontWeight.w600),
            ),
            if (ReceiptQrPayload.rechargeHintForCompany(order.companyName)
                case final hint?) ...[
              SizedBox(height: 6 * s),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11 * s,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
            SizedBox(height: 6 * s),
            _QrCode(
              data: ReceiptQrPayload.forCompany(
                companyName: order.companyName,
                pinCode: item.code,
              ),
              scale: s,
            ),
          ],
          SizedBox(height: 12 * s),
          _Box(
            child: Column(
              children: [
                Text(
                  'المطور',
                  style: TextStyle(
                    fontSize: 12 * s,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4 * s),
                Text('dnzteam.online', style: TextStyle(fontSize: 12 * s)),
                Text('+9647878783591', style: TextStyle(fontSize: 12 * s)),
              ],
            ),
          ),
          SizedBox(height: 10 * s),
          Text(
            'DNZ card يرحب بالجميع',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border, width: 1.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _QrCode extends StatelessWidget {
  const _QrCode({required this.data, this.scale = 1.0});

  final String data;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final side = 96 * scale;
    final value = data.trim().isEmpty ? '—' : data.trim();
    return Center(
      child: QrImageView(
        data: value,
        size: side,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      ),
    );
  }
}
