import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';
import '../../services/admin_service.dart';
import '../../services/functions_service.dart';
import '../../services/purchase_pin_service.dart';
import '../../services/wallet_service.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  String? _deletingUserId;
  String? _resettingPinUserId;
  String? _changingPasswordUserId;
  String? _editingUserId;

  Future<void> _editUser(AppUser user) async {
    final name = TextEditingController(text: user.name);
    final shopName = TextEditingController(text: user.shopName);
    final phone = TextEditingController(text: user.phone);
    final email = TextEditingController(text: user.email);
    final balance = TextEditingController(
      text: user.walletBalance.toStringAsFixed(
        user.walletBalance == user.walletBalance.roundToDouble() ? 0 : 2,
      ),
    );
    final initialDeferred = user.deferredOwed ??
        await WalletService().watchDeferredDepositTotal(user.id).first;
    if (!mounted) return;
    final deferred = TextEditingController(
      text: initialDeferred.toStringAsFixed(
        initialDeferred == initialDeferred.roundToDouble() ? 0 : 2,
      ),
    );
    var role = user.role == 'admin' ? 'admin' : 'shop';
    var status = user.status;
    if (status != 'approved' &&
        status != 'suspended' &&
        status != 'rejected') {
      status = 'approved';
    }
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('تعديل المستخدم'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: shopName,
                      decoration: const InputDecoration(labelText: 'المحل'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'الاسم'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: phone,
                      decoration: const InputDecoration(labelText: 'الهاتف'),
                      keyboardType: TextInputType.phone,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: email,
                      decoration: const InputDecoration(labelText: 'البريد'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'الدور'),
                      items: const [
                        DropdownMenuItem(value: 'shop', child: Text('محل')),
                        DropdownMenuItem(value: 'admin', child: Text('أدمن')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() => role = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'الحالة'),
                      items: const [
                        DropdownMenuItem(
                          value: 'approved',
                          child: Text('نشط / معتمد'),
                        ),
                        DropdownMenuItem(
                          value: 'suspended',
                          child: Text('موقوف'),
                        ),
                        DropdownMenuItem(
                          value: 'rejected',
                          child: Text('مرفوض'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() => status = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: balance,
                      decoration: const InputDecoration(
                        labelText: 'رصيد المحفظة',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final n = double.tryParse(v?.trim() ?? '');
                        if (n == null || n < 0) return 'رصيد غير صالح';
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: deferred,
                      decoration: const InputDecoration(
                        labelText: 'الآجل المستحق عليه',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final n = double.tryParse(v?.trim() ?? '');
                        if (n == null || n < 0) return 'رقم الآجل غير صالح';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) {
      name.dispose();
      shopName.dispose();
      phone.dispose();
      email.dispose();
      balance.dispose();
      deferred.dispose();
      return;
    }

    setState(() => _editingUserId = user.id);
    try {
      await FunctionsService().adminUpdateUser(
        userId: user.id,
        name: name.text.trim(),
        shopName: shopName.text.trim(),
        phone: phone.text.trim(),
        email: email.text.trim(),
        role: role,
        status: status,
        walletBalance: double.parse(balance.text.trim()),
        deferredOwed: double.parse(deferred.text.trim()),
        previousDeferredOwed: initialDeferred,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث بيانات المستخدم')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(e))),
      );
    } finally {
      name.dispose();
      shopName.dispose();
      phone.dispose();
      email.dispose();
      balance.dispose();
      deferred.dispose();
      if (mounted) setState(() => _editingUserId = null);
    }
  }

  Future<void> _sendMessage(BuildContext context, String userId) async {
    final title = TextEditingController(text: 'رسالة من الإدارة');
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إرسال رسالة للمحل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'العنوان'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: body,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'نص الرسالة'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FunctionsService().sendAdminMessage(
        userId: userId,
        title: title.text.trim(),
        body: body.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إرسال الرسالة')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _changePassword(AppUser user) async {
    final password = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغيير كلمة السر'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'المستخدم: ${user.shopName.isEmpty ? user.name : user.shopName}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة السر الجديدة',
                ),
                validator: (v) {
                  if (v == null || v.length < 6) {
                    return '6 أحرف على الأقل';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'تأكيد كلمة السر'),
                validator: (v) {
                  if (v != password.text) return 'غير متطابقة';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      password.dispose();
      confirm.dispose();
      return;
    }

    setState(() => _changingPasswordUserId = user.id);
    try {
      await FunctionsService().adminSetUserPassword(
        userId: user.id,
        password: password.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تغيير كلمة السر بنجاح')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(e))),
      );
    } finally {
      password.dispose();
      confirm.dispose();
      if (mounted) setState(() => _changingPasswordUserId = null);
    }
  }

  Future<void> _resetPurchasePin(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة تعيين رمز الشراء'),
        content: Text(
          'إعادة تعيين رمز شراء الكروت لـ «${user.shopName.isEmpty ? user.name : user.shopName}»؟\n'
          'سيُصفَّر الرمز ويُطفأ السويتش ليضبط المستخدم رمزاً جديداً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إعادة تعيين'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resettingPinUserId = user.id);
    try {
      await PurchasePinService().adminReset(user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إعادة تعيين رمز الشراء')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _resettingPinUserId = null);
    }
  }

  Future<void> _deleteUser(AppUser user, String currentAdminId) async {
    if (user.id == currentAdminId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكنك حذف حسابك الحالي')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح المستخدم'),
        content: Text(
          'هل تريد مسح «${user.shopName.isEmpty ? user.name : user.shopName}» نهائياً؟\n'
          'سيتم حذف حساب الدخول وبيانات المستخدم من النظام.\n'
          'الطلبات السابقة تبقى في السجل.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('مسح نهائي'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingUserId = user.id);
    try {
      await FunctionsService().adminDeleteUser(userId: user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم مسح المستخدم بنجاح')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(e))),
      );
    } finally {
      if (mounted) setState(() => _deletingUserId = null);
    }
  }

  String _cleanError(Object e) {
    return e
        .toString()
        .replaceAll('Exception: ', '')
        .replaceAll('[firebase_functions/', '')
        .split(']')
        .last
        .trim();
  }

  String _statusLabel(AppUser u) {
    final isActive = u.status != 'suspended' && u.status != 'rejected';
    return isActive ? 'نشط' : u.status;
  }

  String _roleLabel(AppUser u) => u.role == 'admin' ? 'أدمن' : 'محل';

  @override
  Widget build(BuildContext context) {
    final adminId = context.watch<AuthProvider>().user?.id ?? '';
    final service = AdminService();
    final wallet = WalletService();

    return Scaffold(
      appBar: AppBar(title: const Text('المستخدمون والمتاجر')),
      body: StreamBuilder<List<AppUser>>(
        stream: service.watchUsers(),
        builder: (context, usersSnap) {
          final users = usersSnap.data ?? [];
          if (usersSnap.connectionState == ConnectionState.waiting &&
              users.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (users.isEmpty) {
            return const Center(child: Text('لا يوجد مستخدمون'));
          }

          return StreamBuilder<Map<String, double>>(
            stream: wallet.watchDeferredDepositTotalsByUser(),
            builder: (context, deferredSnap) {
              final deferred = deferredSnap.data ?? const <String, double>{};
              return LayoutBuilder(
                builder: (context, constraints) {
                  return Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                          minHeight: constraints.maxHeight,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: _UsersExcelTable(
                            users: users,
                            deferredByUser: deferred,
                            adminId: adminId,
                            deletingUserId: _deletingUserId,
                            resettingPinUserId: _resettingPinUserId,
                            changingPasswordUserId: _changingPasswordUserId,
                            editingUserId: _editingUserId,
                            statusLabel: _statusLabel,
                            roleLabel: _roleLabel,
                            onEdit: _editUser,
                            onPrices: (u) => context.push(
                              '/admin/users/${u.id}/prices',
                              extra: u,
                            ),
                            onMessage: (u) => _sendMessage(context, u.id),
                            onChangePassword: _changePassword,
                            onResetPin: _resetPurchasePin,
                            onSuspend: (u) => service.suspendUser(u.id),
                            onActivate: (u) =>
                                service.approveUser(u.id, adminId),
                            onDelete: (u) => _deleteUser(u, adminId),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _UsersExcelTable extends StatelessWidget {
  const _UsersExcelTable({
    required this.users,
    required this.deferredByUser,
    required this.adminId,
    required this.deletingUserId,
    required this.resettingPinUserId,
    required this.changingPasswordUserId,
    required this.editingUserId,
    required this.statusLabel,
    required this.roleLabel,
    required this.onEdit,
    required this.onPrices,
    required this.onMessage,
    required this.onChangePassword,
    required this.onResetPin,
    required this.onSuspend,
    required this.onActivate,
    required this.onDelete,
  });

  final List<AppUser> users;
  final Map<String, double> deferredByUser;
  final String adminId;
  final String? deletingUserId;
  final String? resettingPinUserId;
  final String? changingPasswordUserId;
  final String? editingUserId;
  final String Function(AppUser) statusLabel;
  final String Function(AppUser) roleLabel;
  final ValueChanged<AppUser> onEdit;
  final ValueChanged<AppUser> onPrices;
  final ValueChanged<AppUser> onMessage;
  final ValueChanged<AppUser> onChangePassword;
  final ValueChanged<AppUser> onResetPin;
  final ValueChanged<AppUser> onSuspend;
  final ValueChanged<AppUser> onActivate;
  final ValueChanged<AppUser> onDelete;

  static const _headerBg = Color(0xFFE8EEF5);
  static const _altRow = Color(0xFFF7F9FC);
  static const _border = Color(0xFFC5CDD8);

  @override
  Widget build(BuildContext context) {
    return Table(
      border: TableBorder.all(color: _border, width: 1),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: FixedColumnWidth(160),
        1: FixedColumnWidth(120),
        2: FixedColumnWidth(130),
        3: FixedColumnWidth(70),
        4: FixedColumnWidth(80),
        5: FixedColumnWidth(110),
        6: FixedColumnWidth(130),
        7: FixedColumnWidth(340),
      },
      children: [
        TableRow(
          decoration: const BoxDecoration(color: _headerBg),
          children: [
            _header('المحل'),
            _header('الاسم'),
            _header('الهاتف'),
            _header('الدور'),
            _header('الحالة'),
            _header('الرصيد'),
            _header('مجموع الأجل المودع'),
            _header('الإجراءات'),
          ],
        ),
        for (var i = 0; i < users.length; i++)
          _dataRow(users[i], i.isOdd ? _altRow : Colors.white),
      ],
    );
  }

  TableRow _dataRow(AppUser u, Color bg) {
    final isActive = u.status != 'suspended' && u.status != 'rejected';
    final deferred = u.deferredOwed ?? deferredByUser[u.id] ?? 0;
    final busy = deletingUserId == u.id ||
        resettingPinUserId == u.id ||
        changingPasswordUserId == u.id ||
        editingUserId == u.id;

    return TableRow(
      decoration: BoxDecoration(color: bg),
      children: [
        _cell(u.shopName.isEmpty ? '—' : u.shopName),
        _cell(u.name.isEmpty ? '—' : u.name),
        _cell(u.phone.isEmpty ? '—' : u.phone),
        _cell(roleLabel(u)),
        _cell(statusLabel(u)),
        _cell(Formatters.money(u.walletBalance), alignEnd: true),
        _cell(Formatters.money(deferred), alignEnd: true),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: busy && deletingUserId == u.id
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Wrap(
                  spacing: 0,
                  runSpacing: 0,
                  children: [
                    IconButton(
                      tooltip: 'تعديل',
                      visualDensity: VisualDensity.compact,
                      onPressed: editingUserId != null || deletingUserId != null
                          ? null
                          : () => onEdit(u),
                      icon: editingUserId == u.id
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.edit_outlined, size: 20),
                    ),
                    if (u.role == 'shop')
                      IconButton(
                        tooltip: 'أسعار خاصة',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onPrices(u),
                        icon: const Icon(Icons.price_change_outlined, size: 20),
                      ),
                    IconButton(
                      tooltip: 'إرسال رسالة',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onMessage(u),
                      icon: const Icon(Icons.mail_outline, size: 20),
                    ),
                    IconButton(
                      tooltip: 'تغيير كلمة السر',
                      visualDensity: VisualDensity.compact,
                      onPressed: changingPasswordUserId != null ||
                              deletingUserId != null
                          ? null
                          : () => onChangePassword(u),
                      icon: changingPasswordUserId == u.id
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_reset, size: 20),
                    ),
                    if (u.hasPurchasePin || u.purchasePinEnabled)
                      IconButton(
                        tooltip: 'إعادة تعيين رمز الشراء',
                        visualDensity: VisualDensity.compact,
                        onPressed: resettingPinUserId != null ||
                                deletingUserId != null
                            ? null
                            : () => onResetPin(u),
                        icon: resettingPinUserId == u.id
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.key, size: 20),
                      ),
                    if (isActive)
                      IconButton(
                        tooltip: 'إيقاف',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onSuspend(u),
                        icon: const Icon(Icons.pause_circle, size: 20),
                      ),
                    if (u.status == 'suspended' || u.status == 'rejected')
                      IconButton(
                        tooltip: 'تفعيل',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onActivate(u),
                        icon: const Icon(
                          Icons.play_circle,
                          color: AppColors.accent,
                          size: 20,
                        ),
                      ),
                    if (u.id != adminId)
                      IconButton(
                        tooltip: 'مسح المستخدم',
                        visualDensity: VisualDensity.compact,
                        onPressed:
                            deletingUserId != null ? null : () => onDelete(u),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                          size: 20,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  static Widget _header(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  static Widget _cell(String text, {bool alignEnd = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }
}
