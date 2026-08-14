import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_network_image.dart';
import '../../models/app_user.dart';
import '../../services/admin_service.dart';
import '../../services/functions_service.dart';
import '../../services/storage_service.dart';

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({super.key});

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _phones = TextEditingController();
  final _minBalance = TextEditingController();
  final _search = TextEditingController();

  String _target = 'all';
  String? _imageUrl;
  String? _iconUrl;
  bool _uploadingImage = false;
  bool _uploadingIcon = false;
  bool _sending = false;
  final _selectedIds = <String>{};

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _phones.dispose();
    _minBalance.dispose();
    _search.dispose();
    super.dispose();
  }

  String _contentType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<String?> _pickAndUpload(String folder) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    if (file?.bytes == null) return null;
    return StorageService().uploadImage(
      folder: folder,
      bytes: file!.bytes!,
      fileName: file.name,
      contentType: _contentType(file.extension),
    );
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('العنوان والنص مطلوبان')),
      );
      return;
    }

    List<String>? phones;
    double? minBalance;
    List<String>? userIds;

    if (_target == 'phones') {
      phones = _phones.text
          .split(RegExp(r'[\n,;]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (phones.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أدخل أرقام الهواتف')),
        );
        return;
      }
    }
    if (_target == 'balance') {
      minBalance = double.tryParse(_minBalance.text.trim());
      if (minBalance == null || minBalance < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أدخل حداً صحيحاً للرصيد')),
        );
        return;
      }
    }
    if (_target == 'users') {
      userIds = _selectedIds.toList();
      if (userIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدد مستخدمين من البحث')),
        );
        return;
      }
    }

    setState(() => _sending = true);
    try {
      final result = await FunctionsService().adminSendCampaign(
        title: title,
        body: body,
        imageUrl: _imageUrl,
        iconUrl: _iconUrl,
        target: _target,
        phones: phones,
        minBalance: minBalance,
        userIds: userIds,
      );
      if (!mounted) return;
      final count = result['recipients'] ?? result['delivered'] ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إرسال الإشعار إلى $count مستلم')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e
                .toString()
                .replaceAll('Exception: ', '')
                .replaceAll('[firebase_functions/', '')
                .split(']')
                .last
                .trim(),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: StreamBuilder<List<AppUser>>(
        stream: AdminService().watchUsers(),
        builder: (context, snapshot) {
          final users = (snapshot.data ?? [])
              .where((user) => user.role != 'admin')
              .toList();
          final query = _search.text.trim().toLowerCase();
          final filtered = query.isEmpty
              ? users
              : users.where((user) {
                  return user.phone.toLowerCase().contains(query) ||
                      user.shopName.toLowerCase().contains(query) ||
                      user.name.toLowerCase().contains(query);
                }).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'عنوان الإشعار'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'نص الإشعار'),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ImagePickerCard(
                    label: 'الصورة',
                    url: _imageUrl,
                    uploading: _uploadingImage,
                    onPick: () async {
                      setState(() => _uploadingImage = true);
                      try {
                        final url = await _pickAndUpload('notification_images');
                        if (url != null) setState(() => _imageUrl = url);
                      } finally {
                        if (mounted) setState(() => _uploadingImage = false);
                      }
                    },
                    onClear: () => setState(() => _imageUrl = null),
                  ),
                  _ImagePickerCard(
                    label: 'الأيقونة',
                    url: _iconUrl,
                    uploading: _uploadingIcon,
                    onPick: () async {
                      setState(() => _uploadingIcon = true);
                      try {
                        final url = await _pickAndUpload('notification_icons');
                        if (url != null) setState(() => _iconUrl = url);
                      } finally {
                        if (mounted) setState(() => _uploadingIcon = false);
                      }
                    },
                    onClear: () => setState(() => _iconUrl = null),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'تخصيص الإرسال',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              RadioGroup<String>(
                groupValue: _target,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _target = value);
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: 'all',
                      title: const Text('الكل'),
                    ),
                    RadioListTile<String>(
                      value: 'phones',
                      title: const Text('أرقام هواتف محددة'),
                    ),
                    RadioListTile<String>(
                      value: 'balance',
                      title: const Text('حسابات رصيدها أكبر من'),
                    ),
                    RadioListTile<String>(
                      value: 'users',
                      title: const Text('مستخدمون محددون بالبحث'),
                    ),
                  ],
                ),
              ),
              if (_target == 'phones') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _phones,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'أرقام الهواتف',
                    hintText: 'رقم في كل سطر أو مفصولة بفاصلة',
                  ),
                ),
              ],
              if (_target == 'balance') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _minBalance,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'أكبر من هذا الرصيد',
                  ),
                ),
              ],
              if (_target == 'users') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'بحث برقم الهاتف أو اسم المحل',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 8),
                if (_selectedIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('المحددون: ${_selectedIds.length}'),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: Card(
                    child: filtered.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('لا توجد نتائج'),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final user = filtered[index];
                              final selected = _selectedIds.contains(user.id);
                              final shop = user.shopName.isEmpty
                                  ? user.name
                                  : user.shopName;
                              return CheckboxListTile(
                                value: selected,
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      _selectedIds.add(user.id);
                                    } else {
                                      _selectedIds.remove(user.id);
                                    }
                                  });
                                },
                                title: Text(shop),
                                subtitle: Text(
                                  '${user.phone} • ${Formatters.money(user.walletBalance)}',
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_sending ? 'جاري الإرسال...' : 'إرسال الإشعار'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ImagePickerCard extends StatelessWidget {
  const _ImagePickerCard({
    required this.label,
    required this.url,
    required this.uploading,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final String? url;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          InkWell(
            onTap: uploading ? null : onPick,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.chipBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: uploading
                  ? const Center(child: CircularProgressIndicator())
                  : url == null
                  ? const Center(child: Icon(Icons.add_photo_alternate_outlined))
                  : AppNetworkImage(url: url!, fit: BoxFit.cover),
            ),
          ),
          if (url != null)
            TextButton(onPressed: onClear, child: const Text('إزالة')),
        ],
      ),
    );
  }
}
