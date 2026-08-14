import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';

/// حماية شراء الكروت برمز من 4 أرقام.
class PurchasePinService {
  PurchasePinService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static String hashPin(String pin) {
    final bytes = utf8.encode(pin.trim());
    return sha256.convert(bytes).toString();
  }

  static bool isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  Future<void> enableWithPin({
    required String userId,
    required String pin,
  }) async {
    if (!isValidPin(pin)) {
      throw ArgumentError('الرمز يجب أن يكون 4 أرقام فقط');
    }
    await _db.collection('users').doc(userId).set({
      'purchasePinEnabled': true,
      'purchasePinHash': hashPin(pin),
      'purchasePinUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> disableWithPin({
    required String userId,
    required String pin,
    required String currentHash,
  }) async {
    if (!isValidPin(pin)) {
      throw ArgumentError('الرمز يجب أن يكون 4 أرقام فقط');
    }
    if (hashPin(pin) != currentHash) {
      throw StateError('الرمز غير صحيح');
    }
    await _db.collection('users').doc(userId).set({
      'purchasePinEnabled': false,
      'purchasePinUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  bool verifyPin({required String pin, required String currentHash}) {
    if (!isValidPin(pin)) return false;
    return hashPin(pin) == currentHash;
  }

  /// إعادة تعيين من لوحة الأدمن — يصفّر الحماية ليضبط المستخدم رمزاً جديداً.
  Future<void> adminReset(String userId) async {
    await _db.collection('users').doc(userId).set({
      'purchasePinEnabled': false,
      'purchasePinHash': FieldValue.delete(),
      'purchasePinUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

/// حوار إدخال رمز شراء من 4 أرقام.
Future<String?> promptPurchasePin(
  BuildContext context, {
  required String title,
  String? subtitle,
  bool requireConfirm = false,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PurchasePinDialog(
      title: title,
      subtitle: subtitle,
      requireConfirm: requireConfirm,
    ),
  );
}

class _PurchasePinDialog extends StatefulWidget {
  const _PurchasePinDialog({
    required this.title,
    this.subtitle,
    required this.requireConfirm,
  });

  final String title;
  final String? subtitle;
  final bool requireConfirm;

  @override
  State<_PurchasePinDialog> createState() => _PurchasePinDialogState();
}

class _PurchasePinDialogState extends State<_PurchasePinDialog> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pinController.text.trim();
    if (!PurchasePinService.isValidPin(pin)) {
      setState(() => _error = 'أدخل 4 أرقام فقط');
      return;
    }
    if (widget.requireConfirm && _confirmController.text.trim() != pin) {
      setState(() => _error = 'الرمزان غير متطابقين');
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.subtitle != null) ...[
              Text(
                widget.subtitle!,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _pinController,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'الرمز (4 أرقام)',
                counterText: '',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            if (widget.requireConfirm) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'تأكيد الرمز',
                  counterText: '',
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('تأكيد'),
        ),
      ],
    );
  }
}
