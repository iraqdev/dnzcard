import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_network_image.dart';
import '../../models/fazer_models.dart';
import '../../models/app_settings.dart';
import '../../services/fazer_service.dart';
import '../../services/settings_service.dart';

class AdminFazerPage extends StatefulWidget {
  const AdminFazerPage({super.key});

  @override
  State<AdminFazerPage> createState() => _AdminFazerPageState();
}

class _AdminFazerPageState extends State<AdminFazerPage> {
  final _service = FazerService();
  final _settings = SettingsService();
  String? _selectedCategoryId;
  String? _selectedCategoryKind;
  String _search = '';
  bool _syncingGift = false;
  bool _syncingKeys = false;
  bool _syncingTopups = false;
  bool _syncingTelegram = false;
  bool _syncingOffers = false;
  String? _balanceText;
  String? _busyOfferId;
  bool _savingFazerToggle = false;

  Future<void> _setFazerEnabled(bool enabled) async {
    setState(() => _savingFazerToggle = true);
    try {
      await _settings.saveFazerEnabled(enabled);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'تم تفعيل فايزr — تظهر للمحلات'
                : 'تم إيقاف فايزr — مخفية عن المحلات',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _savingFazerToggle = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshBalance();
  }

  Future<void> _refreshBalance() async {
    try {
      final data = await _service.getBalance();
      if (!mounted) return;
      setState(() {
        _balanceText =
            '${data['balance'] ?? '—'} ${data['currency'] ?? 'USD'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _balanceText = 'تعذر التحميل');
    }
  }

  Future<void> _syncGiftCategories() async {
    if (_syncingGift) return;
    setState(() => _syncingGift = true);
    try {
      final result = await _service.syncCategories();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تمت مزامنة ${result['synced'] ?? 0} فئة بطاقات'),
        ),
      );
      await _refreshBalance();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _syncingGift = false);
    }
  }

  Future<void> _syncGameKeyCategories() async {
    if (_syncingKeys) return;
    setState(() => _syncingKeys = true);
    try {
      final result = await _service.syncGameKeyCategories();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تمت مزامنة ${result['synced'] ?? 0} فئة مفاتيح'),
        ),
      );
      await _refreshBalance();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _syncingKeys = false);
    }
  }

  Future<void> _syncTopupCategories() async {
    if (_syncingTopups) return;
    setState(() => _syncingTopups = true);
    try {
      final result = await _service.syncTopupCategories();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تمت مزامنة ${result['synced'] ?? 0} فئة شحن بالاي دي'),
        ),
      );
      await _refreshBalance();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _syncingTopups = false);
    }
  }

  Future<void> _syncTelegram() async {
    if (_syncingTelegram) return;
    setState(() => _syncingTelegram = true);
    try {
      final result = await _service.syncTelegramCatalog();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تمت مزامنة تليجرام: ${result['synced'] ?? 0} عرض'),
        ),
      );
      await _refreshBalance();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _syncingTelegram = false);
    }
  }

  Future<void> _syncOffers(String categoryId, {String? kind}) async {
    if (_syncingOffers) return;
    final isTelegram =
        kind == 'telegram_stars' || kind == 'telegram_premium';
    setState(() => _syncingOffers = true);
    try {
      final result = isTelegram
          ? await _service.syncTelegramCatalog()
          : await _service.syncCategoryOffers(categoryId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تمت مزامنة ${result['synced'] ?? 0} عرض'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _syncingOffers = false);
    }
  }

  Future<void> _savePrice(FazerOffer offer, String raw) async {
    final trimmed = raw.trim();
    final price = trimmed.isEmpty ? null : double.tryParse(trimmed);
    if (trimmed.isNotEmpty && (price == null || price < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل سعراً صحيحاً بالدينار')),
      );
      return;
    }
    setState(() => _busyOfferId = offer.id);
    try {
      await _service.setKushkPrice(
        offerId: offer.id,
        kushkPrice: price == null || price == 0 ? null : price,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            price == null || price == 0
                ? 'تم إخفاء العرض عن المستخدمين'
                : 'تم حفظ سعر DNZ card: ${Formatters.money(price)}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busyOfferId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فايزر — بطاقات / مفاتيح / تليجرام'),
        actions: [
          IconButton(
            tooltip: 'تحديث رصيد فايزر',
            onPressed: _refreshBalance,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: StreamBuilder<AppSettings>(
        stream: _settings.watch(),
        builder: (context, settingsSnap) {
          final fazerEnabled = settingsSnap.data?.fazerEnabled ?? true;
          return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: SwitchListTile(
                title: const Text(
                  'إظهار فايزr في التطبيق',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  fazerEnabled
                      ? 'كل بيانات فايزr ظاهرة للمحلات'
                      : 'فايزr مخفية بالكامل عن المحلات',
                ),
                value: fazerEnabled,
                onChanged: _savingFazerToggle ? null : _setFazerEnabled,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'رصيد فايزر: ${_balanceText ?? '...'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _syncingGift ? null : _syncGiftCategories,
                      icon: _syncingGift
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.card_giftcard_outlined),
                      label: Text(
                        _syncingGift ? 'جاري...' : 'مزامنة البطاقات',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _syncingKeys ? null : _syncGameKeyCategories,
                      icon: _syncingKeys
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.videogame_asset_outlined),
                      label: Text(
                        _syncingKeys ? 'جاري...' : 'مزامنة Game Keys',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _syncingTopups ? null : _syncTopupCategories,
                      icon: _syncingTopups
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.person_pin_outlined),
                      label: Text(
                        _syncingTopups ? 'جاري...' : 'مزامنة الشحن بالاي دي',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _syncingTelegram ? null : _syncTelegram,
                      icon: _syncingTelegram
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text(
                        _syncingTelegram ? 'جاري...' : 'مزامنة Telegram',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'بحث عن فئة...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: MediaQuery.sizeOf(context).width >= 900 ? 320 : 260,
                  child: StreamBuilder<List<FazerCategory>>(
                    stream: _service.watchCategories(),
                    builder: (context, snap) {
                      final all = snap.data ?? [];
                      final q = _search.toLowerCase();
                      final cats = q.isEmpty
                          ? all
                          : all
                              .where(
                                (c) =>
                                    c.name.toLowerCase().contains(q) ||
                                    c.id.toLowerCase().contains(q) ||
                                    c.kindLabel.contains(_search),
                              )
                              .toList();
                      if (snap.connectionState == ConnectionState.waiting &&
                          cats.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (cats.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'لا توجد فئات.\nزامن البطاقات أو Game Keys أو Telegram.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: cats.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final c = cats[index];
                          final selected = c.id == _selectedCategoryId;
                          return ListTile(
                            selected: selected,
                            selectedTileColor: AppColors.chipBg,
                            leading: SizedBox(
                              width: 40,
                              height: 40,
                              child: c.imageUrl.isEmpty
                                  ? Icon(
                                      c.isTelegram
                                          ? Icons.send_outlined
                                          : c.kind == 'game_key'
                                              ? Icons.videogame_asset_outlined
                                              : Icons.card_giftcard,
                                    )
                                  : AppNetworkImage(
                                      url: c.imageUrl,
                                      fit: BoxFit.cover,
                                      fallbackIcon: Icons.card_giftcard,
                                    ),
                            ),
                            title: Text(
                              c.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              '${c.kindLabel} · ${c.id}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            onTap: () {
                              setState(() {
                                _selectedCategoryId = c.id;
                                _selectedCategoryKind = c.kind;
                              });
                              _syncOffers(c.id, kind: c.kind);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildOffersPane()),
              ],
            ),
          ),
        ],
      );
        },
      ),
    );
  }

  Widget _buildOffersPane() {
    final categoryId = _selectedCategoryId;
    if (categoryId == null) {
      return const Center(
        child: Text('اختر فئة من اليسار لعرض الأسعار وتعيين سعر DNZ card'),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'عروض الفئة — الفارغ لا يظهر للمستخدم',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _syncingOffers
                    ? null
                    : () => _syncOffers(
                          categoryId,
                          kind: _selectedCategoryKind,
                        ),
                icon: _syncingOffers
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, size: 18),
                label: const Text('تحديث العروض'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<FazerOffer>>(
            stream: _service.watchOffersForCategory(categoryId),
            builder: (context, snap) {
              final offers = snap.data ?? [];
              if (snap.connectionState == ConnectionState.waiting &&
                  offers.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (offers.isEmpty) {
                return const Center(
                  child: Text('لا توجد عروض — اضغط تحديث العروض'),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: offers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final o = offers[index];
                  return _OfferPriceRow(
                    offer: o,
                    busy: _busyOfferId == o.id,
                    onSave: (raw) => _savePrice(o, raw),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OfferPriceRow extends StatefulWidget {
  const _OfferPriceRow({
    required this.offer,
    required this.busy,
    required this.onSave,
  });

  final FazerOffer offer;
  final bool busy;
  final ValueChanged<String> onSave;

  @override
  State<_OfferPriceRow> createState() => _OfferPriceRowState();
}

class _OfferPriceRowState extends State<_OfferPriceRow> {
  late final TextEditingController _price;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(
      text: widget.offer.kushkPrice == null
          ? ''
          : widget.offer.kushkPrice!.toStringAsFixed(
              widget.offer.kushkPrice ==
                      widget.offer.kushkPrice!.roundToDouble()
                  ? 0
                  : 2,
            ),
    );
  }

  @override
  void didUpdateWidget(covariant _OfferPriceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offer.kushkPrice != widget.offer.kushkPrice &&
        !widget.busy) {
      final next = widget.offer.kushkPrice == null
          ? ''
          : widget.offer.kushkPrice!.toStringAsFixed(
              widget.offer.kushkPrice ==
                      widget.offer.kushkPrice!.roundToDouble()
                  ? 0
                  : 2,
            );
      if (_price.text != next) _price.text = next;
    }
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: o.isPriced ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'تكلفة فايزر: \$${o.priceUsd.toStringAsFixed(4)} | مخزون: ${o.stock}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: TextField(
              controller: _price,
              enabled: !widget.busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'سعر DNZ card',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: widget.busy ? null : () => widget.onSave(_price.text),
            child: widget.busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
