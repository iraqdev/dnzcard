import 'dart:async';

import '../../core/widgets/app_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/brief_print_spinner.dart';
import '../../core/widgets/notification_bell.dart';
import '../../core/widgets/press_scale.dart';
import '../../models/catalog_models.dart';
import '../../models/fazer_models.dart';
import '../../models/order_model.dart';
import '../../printer/printer_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../models/user_custom_price.dart';
import '../../services/custom_price_service.dart';
import '../../models/app_settings.dart';
import '../../services/fazer_service.dart';
import '../../services/order_service.dart';
import '../../services/purchase_pin_service.dart';
import '../../services/settings_service.dart';
import 'card_receipt_view.dart';
import 'product_card_widget.dart';

final _storeCustomPrices = CustomPriceService();
final _fazerService = FazerService();
final _settingsService = SettingsService();

const _fazerPrefix = 'fazer:';

bool _isFazerSelection(String? id) => isFazerCatalogSelection(id);

class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final selectedCompanyId = context.select(
      (CatalogProvider c) => c.selectedCompanyId,
    );
    final companies = context.select((CatalogProvider c) => c.companies);
    final companiesLoaded =
        context.select((CatalogProvider c) => c.companiesLoaded);
    final isFazerAll = selectedCompanyId == kFazerAllCompanyId;
    final isFazerGameKeys = selectedCompanyId == kFazerGameKeysCompanyId;
    final isFazerWorld = selectedCompanyId == kFazerWorldCompanyId;
    final isFazerTopups = selectedCompanyId == kFazerTopupsCompanyId;
    final isFazerGkCategory =
        selectedCompanyId != null &&
        selectedCompanyId.startsWith(kFazerGkPrefix);
    final isFazerWorldCategory =
        selectedCompanyId != null &&
        selectedCompanyId.startsWith(kFazerWorldPrefix);
    final isFazerTopupCategory =
        selectedCompanyId != null &&
        selectedCompanyId.startsWith(kFazerTopupPrefix);
    final isFazer = _isFazerSelection(selectedCompanyId);
    final selectedCompany = selectedCompanyId == null
        ? null
        : context.select((CatalogProvider c) => c.companyOf(selectedCompanyId));
    final userId = context.select((AuthProvider a) => a.user?.id);
    final catalog = context.read<CatalogProvider>();
    final hasSelection = selectedCompanyId != null;

    return StreamBuilder<AppSettings>(
      stream: _settingsService.watch(),
      builder: (context, settingsSnap) {
        // إن تعذّر قراءة الإعدادات نستخدم الافتراضي 1470 — وإلا السعر الحي من Firestore.
        final saleRate = settingsSnap.hasError
            ? kFazerGameKeyIqdRate
            : (settingsSnap.data?.gameKeySaleRate ?? kFazerGameKeyIqdRate);
        final fazerBalanceUsd = settingsSnap.hasError
            ? null
            : settingsSnap.data?.fazerBalanceUsd;
        final fazerEnabled = settingsSnap.hasError
            ? true
            : (settingsSnap.data?.fazerEnabled ?? true);
        final shopCompanies = fazerEnabled
            ? companies
            : companies.where((c) => !c.isFazerSpecial).toList();
        if (!fazerEnabled && isFazer) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) catalog.selectCompany(null);
          });
        }
        return StreamBuilder<List<FazerCategory>>(
      stream: _fazerService.watchGameKeyCategories(),
      builder: (context, gamesSnap) {
        final gameCategories = gamesSnap.data ?? const <FazerCategory>[];
        return StreamBuilder<List<FazerCategory>>(
      stream: _fazerService.watchGiftCategories(),
      builder: (context, giftsSnap) {
        final giftCategories = giftsSnap.data ?? const <FazerCategory>[];
        return StreamBuilder<List<FazerCategory>>(
      stream: _fazerService.watchTopupCategories(),
      builder: (context, topupsSnap) {
        final topupCategories = topupsSnap.data ?? const <FazerCategory>[];
        return StreamBuilder<List<FazerOffer>>(
      stream: _fazerService.watchPricedOffers(),
      builder: (context, fazerSnap) {
        final pricedOffers = (fazerSnap.data ?? const <FazerOffer>[])
            .where((o) => !o.isGameKey && !o.isTopup)
            .toList();
        final pricedCategoryIds = {
          for (final o in pricedOffers) o.categoryId,
        };
        final isFazerCardCategory =
            fazerEnabled &&
            isFazer &&
            !isFazerAll &&
            !isFazerGameKeys &&
            !isFazerWorld &&
            !isFazerTopups &&
            !isFazerGkCategory &&
            !isFazerWorldCategory &&
            !isFazerTopupCategory;
        final selectedId = selectedCompanyId ?? '';
        final fazerCategoryId = isFazerCardCategory
            ? selectedId.substring(_fazerPrefix.length)
            : isFazerGkCategory
                ? selectedId.substring(kFazerGkPrefix.length)
                : isFazerWorldCategory
                    ? selectedId.substring(kFazerWorldPrefix.length)
                    : isFazerTopupCategory
                        ? selectedId.substring(kFazerTopupPrefix.length)
                        : null;
        final categoryOffers = isFazerCardCategory && fazerCategoryId != null
            ? pricedOffers
                .where((o) => o.categoryId == fazerCategoryId)
                .toList()
            : const <FazerOffer>[];
        final gameTitle = fazerCategoryId == null
            ? ''
            : gameCategories
                .where((g) => g.id == fazerCategoryId)
                .map((g) => g.name)
                .cast<String>()
                .followedBy(const [''])
                .first;
        final worldCatTitle = fazerCategoryId == null
            ? ''
            : giftCategories
                .where((g) => g.id == fazerCategoryId)
                .map((g) => g.name)
                .cast<String>()
                .followedBy(const [''])
                .first;
        final topupCatTitle = fazerCategoryId == null
            ? ''
            : topupCategories
                .where((g) => g.id == fazerCategoryId)
                .map((g) => g.name)
                .cast<String>()
                .followedBy(const [''])
                .first;
        final categoryTitle = isFazerGkCategory && gameTitle.isNotEmpty
            ? gameTitle
            : isFazerWorldCategory && worldCatTitle.isNotEmpty
                ? worldCatTitle
                : isFazerTopupCategory && topupCatTitle.isNotEmpty
                    ? topupCatTitle
                    : categoryOffers.isNotEmpty
                        ? categoryOffers.first.categoryName
                        : (fazerCategoryId ?? '');

        String title = 'الشركات';
        if (isFazerGkCategory ||
            isFazerCardCategory ||
            isFazerWorldCategory ||
            isFazerTopupCategory) {
          title = categoryTitle.isEmpty ? 'البطاقات' : categoryTitle;
        } else if (isFazerAll) {
          title = selectedCompany?.name ?? 'جميع البطاقات';
        } else if (isFazerGameKeys) {
          title = selectedCompany?.name ?? 'مفاتيح العاب';
        } else if (isFazerWorld) {
          title = selectedCompany?.name ?? 'جميع البطاقات بالعالم';
        } else if (isFazerTopups) {
          title = selectedCompany?.name ?? 'شحن بالاي دي';
        } else if (selectedCompany != null) {
          title = selectedCompany.name;
        }

        return Scaffold(
          appBar: AppBar(
            leading: !hasSelection
                ? null
                : IconButton(
                    tooltip: isFazerGkCategory
                        ? 'رجوع إلى مفاتيح العاب'
                        : isFazerWorldCategory
                            ? 'رجوع إلى جميع البطاقات بالعالم'
                            : isFazerTopupCategory
                                ? 'رجوع إلى شحن بالاي دي'
                                : isFazerCardCategory
                                    ? 'رجوع إلى جميع البطاقات'
                                    : 'رجوع إلى الشركات',
                    onPressed: () {
                      if (isFazerGkCategory) {
                        catalog.selectCompany(kFazerGameKeysCompanyId);
                      } else if (isFazerWorldCategory) {
                        catalog.selectCompany(kFazerWorldCompanyId);
                      } else if (isFazerTopupCategory) {
                        catalog.selectCompany(kFazerTopupsCompanyId);
                      } else if (isFazerCardCategory) {
                        catalog.selectCompany(kFazerAllCompanyId);
                      } else {
                        catalog.selectCompany(null);
                      }
                    },
                    icon: const Icon(Icons.arrow_forward),
                  ),
            title: AppLogoTitle(title),
            actions: const [NotificationBell()],
          ),
          body: Column(
            children: [
              if (shopCompanies.isNotEmpty && !isFazer)
                _CompanyShortcutsBar(
                  companies: shopCompanies
                      .where(
                        (c) =>
                            !c.isFazerAll ||
                            (fazerEnabled && pricedOffers.isNotEmpty),
                      )
                      .toList(),
                  selectedId: selectedCompanyId,
                  onSelected: (id) => catalog.selectCompany(id),
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: KeyedSubtree(
                    key: ValueKey(selectedCompanyId ?? 'hub'),
                    child: !hasSelection
                        ? _CompaniesHub(
                            companies: shopCompanies
                                .where(
                                  (c) =>
                                      !c.isFazerAll ||
                                      (fazerEnabled &&
                                          pricedOffers.isNotEmpty),
                                )
                                .toList(),
                            loading: !companiesLoaded,
                            onSelected: (company) =>
                                catalog.selectCompany(company.id),
                          )
                        : fazerEnabled && isFazerAll
                            ? _FazerCategoriesView(
                                offers: pricedOffers,
                                onCategorySelected: (categoryId) =>
                                    catalog.selectCompany(
                                  '$_fazerPrefix$categoryId',
                                ),
                              )
                            : fazerEnabled && isFazerGameKeys
                                ? _GameKeysCategoriesView(
                                    categories: gameCategories,
                                    onGameSelected: (categoryId) =>
                                        catalog.selectCompany(
                                      '$kFazerGkPrefix$categoryId',
                                    ),
                                  )
                                : fazerEnabled && isFazerWorld
                                    ? _FazerWorldCategoriesView(
                                        giftCategories: giftCategories,
                                        pricedCategoryIds: pricedCategoryIds,
                                        onCategorySelected: (categoryId) =>
                                            catalog.selectCompany(
                                          '$kFazerWorldPrefix$categoryId',
                                        ),
                                      )
                                : fazerEnabled && isFazerTopups
                                    ? _FazerTopupCategoriesView(
                                        categories: topupCategories,
                                        onCategorySelected: (categoryId) =>
                                            catalog.selectCompany(
                                          '$kFazerTopupPrefix$categoryId',
                                        ),
                                      )
                                : fazerEnabled && isFazerGkCategory
                                    ? _GameKeyOffersBody(
                                        key: ValueKey(
                                          'gk-$fazerCategoryId-$saleRate-$fazerBalanceUsd',
                                        ),
                                        categoryId: fazerCategoryId!,
                                        saleRate: saleRate,
                                        fazerBalanceUsd: fazerBalanceUsd,
                                        onBuy: (offer) => _chooseFazerPurchase(
                                          context,
                                          offer,
                                          saleRate,
                                          fazerBalanceUsd: fazerBalanceUsd,
                                        ),
                                      )
                                    : fazerEnabled && isFazerWorldCategory
                                        ? _FazerWorldOffersBody(
                                        key: ValueKey(
                                          'world-$fazerCategoryId-$saleRate-$fazerBalanceUsd',
                                        ),
                                        categoryId: fazerCategoryId!,
                                        saleRate: saleRate,
                                        fazerBalanceUsd: fazerBalanceUsd,
                                        onBuy: (offer) =>
                                            _chooseFazerPurchase(
                                          context,
                                          offer,
                                          saleRate,
                                          fazerBalanceUsd: fazerBalanceUsd,
                                        ),
                                      )
                                    : fazerEnabled && isFazerTopupCategory
                                        ? _FazerTopupOffersBody(
                                            key: ValueKey(
                                              'topup-$fazerCategoryId-$saleRate-$fazerBalanceUsd',
                                            ),
                                            categoryId: fazerCategoryId!,
                                            saleRate: saleRate,
                                            fazerBalanceUsd: fazerBalanceUsd,
                                            onBuy: (offer) =>
                                                _chooseFazerPurchase(
                                              context,
                                              offer,
                                              saleRate,
                                              fazerBalanceUsd: fazerBalanceUsd,
                                            ),
                                          )
                                    : fazerEnabled && isFazerCardCategory
                                        ? _FazerCategoryOffersView(
                                            key: ValueKey(
                                              'card-$fazerCategoryId-$saleRate-$fazerBalanceUsd',
                                            ),
                                            categoryId: fazerCategoryId!,
                                            offers: categoryOffers,
                                            fazerBalanceUsd: fazerBalanceUsd,
                                            priceOf: (offer) =>
                                                offer.gameKeyIqdPrice(saleRate),
                                            onBuy: (offer) =>
                                                _chooseFazerPurchase(
                                              context,
                                              offer,
                                              saleRate,
                                              fazerBalanceUsd: fazerBalanceUsd,
                                            ),
                                          )
                                        : selectedCompany == null
                                            ? const Center(
                                                child: Text(
                                                  'الشركة غير موجودة',
                                                ),
                                              )
                                            : _PricedProductsBody(
                                                company: selectedCompany,
                                                userId: userId,
                                                onSearch: catalog.search,
                                                onBuy: (product) =>
                                                    _choosePurchaseAction(
                                                  context,
                                                  product,
                                                ),
                                              ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
      },
    );
      },
    );
      },
    );
      },
    );
  }

  /// يعيد رمز الشراء المُدخل للتحقق منه على الخادم، أو '' إذا كانت الحماية
  /// غير مفعّلة. يعيد null عند الإلغاء أو فشل التحقق المحلي.
  Future<String?> _ensurePurchasePin(BuildContext context) async {
    final user = context.read<AuthProvider>().user;
    if (user?.purchasePinEnabled != true) return '';
    final hash = user!.purchasePinHash;
    if (hash == null || hash.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رمز الشراء غير مضبوط. عيّنه من الملف الشخصي'),
        ),
      );
      return null;
    }
    final pin = await promptPurchasePin(
      context,
      title: 'رمز شراء الكارت',
      subtitle: 'أدخل الرمز المكوّن من 4 أرقام للمتابعة.',
    );
    if (pin == null || !context.mounted) return null;
    if (!PurchasePinService().verifyPin(pin: pin, currentHash: hash)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرمز غير صحيح')),
      );
      return null;
    }
    return pin;
  }

  Future<void> _chooseFazerPurchase(
    BuildContext context,
    FazerOffer offer,
    double saleRate, {
    double? fazerBalanceUsd,
  }) async {
    if (!offer.fazerBalanceCovers(fazerBalanceUsd)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('نفذ — رصيد فايزr غير كافٍ')),
      );
      return;
    }
    final price = offer.gameKeyIqdPrice(saleRate);
    String? telegramUsername;
    Map<String, String>? topupFields;
    if (offer.isTelegram) {
      telegramUsername = await _askTelegramUsername(context);
      if (telegramUsername == null || !context.mounted) return;
    }
    if (offer.isTopup) {
      topupFields = await _askTopupFields(context, offer.categoryId);
      if (topupFields == null || !context.mounted) return;
    }

    final action = await showModalBottomSheet<_PurchaseAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'شراء ${offer.displayTitle}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                offer.isTelegram
                    ? 'سيتم الشحن إلى @$telegramUsername واستقطاع ${Formatters.money(price)} فوراً'
                    : offer.isTopup
                        ? 'سيتم شحن اللاعب واستقطاع ${Formatters.money(price)} فوراً'
                        : 'سيتم استقطاع ${Formatters.money(price)} من رصيدك فوراً',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, _PurchaseAction.show),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('إظهار'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, _PurchaseAction.print),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('طباعة'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (action == null || !context.mounted) return;
    final pin = await _ensurePurchasePin(context);
    if (pin == null || !context.mounted) return;
    await _purchaseFazer(
      context,
      offer,
      print: action == _PurchaseAction.print,
      telegramUsername: telegramUsername,
      topupFields: topupFields,
      pin: pin,
    );
  }

  Future<Map<String, String>?> _askTopupFields(
    BuildContext context,
    String categoryId,
  ) async {
    final category = await _fazerService.getCategory(categoryId);
    if (!context.mounted) return null;
    final fields = (category?.buyerFields.isNotEmpty == true)
        ? category!.buyerFields
        : const [FazerBuyerField(key: 'player_id', label: 'معرّف اللاعب')];

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _TopupFieldsDialog(
        categoryId: categoryId,
        categoryName: category?.name ?? '',
        fields: fields,
        requiresValidate: category?.supportsValidateId == true,
      ),
    );
  }

  Future<String?> _askTelegramUsername(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => const _TelegramUsernameDialog(),
    );
  }

  Future<void> _purchaseFazer(
    BuildContext context,
    FazerOffer offer, {
    required bool print,
    String? telegramUsername,
    Map<String, String>? topupFields,
    String pin = '',
  }) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              child: Text(
                'جاري الشراء من DNZ card...',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );

    late final OrderModel order;
    try {
      order = await _fazerService.purchaseOffer(
        offerId: offer.id,
        telegramUsername: telegramUsername,
        fields: topupFields,
        pin: pin,
      );
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await _handlePurchaseError(context, error);
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final isPending =
        order.status == 'processing' || order.status == 'ordering';
    final successTitle = isPending
        ? 'تم الخصم والطلب قيد التنفيذ'
        : 'تم الشراء وخصم المبلغ';
    final printSuccessText = isPending
        ? 'تم الخصم والطباعة — الشحن قيد التنفيذ'
        : 'تم الخصم وطباعة الكارت بنجاح';
    final printFailTitle = isPending
        ? 'تم الخصم وتعذرت الطباعة — الطلب قيد التنفيذ'
        : 'تم الخصم وتعذرت الطباعة — البطاقة محفوظة';

    if (print) {
      final dismissSpinner = showBriefPrintSpinner(context);
      try {
        await PrinterService().printOrder(
          order,
          shopName: user.shopName,
          context: context,
        );
        await OrderService().markPrinted(order.id);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(child: Text(printSuccessText)),
              ],
            ),
          ),
        );
        return;
      } catch (_) {
        if (!context.mounted) return;
        await _showReceipt(
          context,
          order,
          shopName: user.shopName,
          title: printFailTitle,
        );
        return;
      } finally {
        dismissSpinner();
      }
    }

    await _showReceipt(
      context,
      order,
      shopName: user.shopName,
      title: successTitle,
    );
  }

  Future<void> _choosePurchaseAction(
    BuildContext context,
    Product product,
  ) async {
    final action = await showModalBottomSheet<_PurchaseAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'شراء كارت فئة ${product.name}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'سيتم استقطاع ${Formatters.money(product.price)} من رصيدك',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, _PurchaseAction.show),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('إظهار'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, _PurchaseAction.print),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('طباعة'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (action == null || !context.mounted) return;
    final pin = await _ensurePurchasePin(context);
    if (pin == null || !context.mounted) return;
    await _purchase(
      context,
      product,
      print: action == _PurchaseAction.print,
      pin: pin,
    );
  }

  Future<void> _purchase(
    BuildContext context,
    Product product, {
    required bool print,
    String pin = '',
  }) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    late final OrderModel order;
    try {
      order = await OrderService().purchaseProductViaServer(
        productId: product.id,
        quantity: 1,
        pin: pin,
      );
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await _handlePurchaseError(context, error);
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (print) {
      final dismissSpinner = showBriefPrintSpinner(context);
      try {
        await PrinterService().printOrder(
          order,
          shopName: user.shopName,
          context: context,
        );
        await OrderService().markPrinted(order.id);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.accent),
                SizedBox(width: 8),
                Expanded(child: Text('تم الخصم وطباعة الكارت بنجاح')),
              ],
            ),
          ),
        );
        return;
      } catch (_) {
        if (!context.mounted) return;
        await _showReceipt(
          context,
          order,
          shopName: user.shopName,
          title: 'تم الخصم وتعذرت الطباعة — البطاقة محفوظة',
        );
        return;
      } finally {
        dismissSpinner();
      }
    }

    await _showReceipt(
      context,
      order,
      shopName: user.shopName,
      title: 'تم الشراء وخصم المبلغ',
    );
  }

  Future<void> _showReceipt(
    BuildContext context,
    OrderModel order, {
    required String shopName,
    required String title,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: CardReceiptView(order: order, shopName: shopName),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تم'),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePurchaseError(BuildContext context, Object error) async {
    final text = _errorText(error);
    if (_isInsufficientBalance(text)) {
      final goWallet = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('رصيد غير كافٍ'),
          content: const Text('ليس لديك رصيد كافٍ في المحفظة لإتمام الشراء.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تعبئة المحفظة'),
            ),
          ],
        ),
      );
      if (goWallet == true && context.mounted) {
        context.go('/wallet');
      }
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  bool _isInsufficientBalance(String text) {
    final t = text.replaceAll('ٍ', 'ي').replaceAll('ً', '');
    return t.contains('رصيد المحفظة غير كافي') ||
        t.contains('رصيد غير كافي') ||
        (t.contains('رصيد') && t.contains('غير كافي'));
  }

  String _errorText(Object error) {
    return error
        .toString()
        .replaceAll('Bad state: ', '')
        .replaceAll('Invalid argument(s): ', '')
        .replaceAll('Exception: ', '')
        .replaceAll('[firebase_functions/', '')
        .split(']')
        .last
        .trim();
  }
}

enum _PurchaseAction { show, print }

class _CompaniesHub extends StatelessWidget {
  const _CompaniesHub({
    required this.companies,
    required this.onSelected,
    this.loading = false,
  });

  final List<Company> companies;
  final ValueChanged<Company> onSelected;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (companies.isEmpty) {
      return const Center(child: Text('لا توجد شركات أو بطاقات متاحة حالياً'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.1,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: companies.length,
      itemBuilder: (context, index) {
        final company = companies[index];
        return _CompanyTile(
          name: company.name,
          imageUrl: company.logoUrl,
                      fallbackIcon: company.isFazerGameKeys
              ? Icons.videogame_asset_outlined
              : company.isFazerTopups
                  ? Icons.person_pin_outlined
                  : company.isFazerWorld
                      ? Icons.public_outlined
                      : company.isFazerAll
                          ? Icons.card_giftcard
                          : Icons.business,
          onTap: () => onSelected(company),
        );
      },
    );
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({
    required this.name,
    required this.imageUrl,
    required this.fallbackIcon,
    required this.onTap,
  });

  final String name;
  final String imageUrl;
  final IconData fallbackIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: PressScale(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Expanded(
                  child: imageUrl.isEmpty
                      ? Icon(fallbackIcon, size: 56, color: AppColors.primary)
                      : AppNetworkImage(
                          url: imageUrl,
                          fallbackIcon: fallbackIcon,
                        ),
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FazerCategoriesView extends StatefulWidget {
  const _FazerCategoriesView({
    required this.offers,
    required this.onCategorySelected,
  });

  final List<FazerOffer> offers;
  final ValueChanged<String> onCategorySelected;

  @override
  State<_FazerCategoriesView> createState() => _FazerCategoriesViewState();
}

class _FazerCategoriesViewState extends State<_FazerCategoriesView> {
  String _query = '';

  List<_FazerCategoryItem> _categories(List<FazerCategory> meta) {
    final byId = {for (final c in meta) c.id: c};
    final map = <String, _FazerCategoryItem>{};
    for (final o in widget.offers) {
      final existing = map[o.categoryId];
      final cat = byId[o.categoryId];
      final image = (cat?.coverUrl.isNotEmpty == true)
          ? cat!.coverUrl
          : o.imageUrl;
      if (existing == null) {
        map[o.categoryId] = _FazerCategoryItem(
          categoryId: o.categoryId,
          name: o.categoryName.isEmpty ? o.categoryId : o.categoryName,
          imageUrl: image,
          offerCount: 1,
          sortOrder: cat?.sortOrder ?? 999999,
        );
      } else {
        map[o.categoryId] = existing.copyWith(
          offerCount: existing.offerCount + 1,
          imageUrl: existing.imageUrl.isEmpty ? image : existing.imageUrl,
        );
      }
    }
    final list = map.values.toList()
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
      });
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FazerCategory>>(
      stream: _fazerService.watchGiftCategories(),
      builder: (context, metaSnap) {
        final cats = _categories(metaSnap.data ?? const <FazerCategory>[]);
        return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Autocomplete<String>(
            optionsBuilder: (textEditingValue) {
              final q = textEditingValue.text.trim().toLowerCase();
              final names = widget.offers
                  .map(
                    (o) => o.categoryName.isEmpty
                        ? o.categoryId
                        : o.categoryName,
                  )
                  .toSet()
                  .toList()
                ..sort();
              if (q.isEmpty) return names.take(8);
              return names.where((n) => n.toLowerCase().contains(q)).take(10);
            },
            onSelected: (value) => setState(() => _query = value),
            fieldViewBuilder: (context, controller, focusNode, onSubmit) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: (v) => setState(() => _query = v),
                onSubmitted: (_) => onSubmit(),
                decoration: const InputDecoration(
                  hintText: 'بحث سريع عن فئة...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              final opts = options.toList();
              if (opts.isEmpty) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.topRight,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 220,
                      maxWidth: 420,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: opts.length,
                      itemBuilder: (context, index) {
                        final option = opts[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            option,
                            style: const TextStyle(fontSize: 13),
                          ),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: cats.isEmpty
              ? const Center(child: Text('لا توجد فئات مطابقة للبحث'))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.05,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: cats.length,
                  itemBuilder: (context, index) {
                    final cat = cats[index];
                    return _CompanyTile(
                      name: cat.name,
                      imageUrl: cat.imageUrl,
                      fallbackIcon: Icons.card_giftcard,
                      onTap: () => widget.onCategorySelected(cat.categoryId),
                    );
                  },
                ),
        ),
      ],
    );
      },
    );
  }
}

class _FazerCategoryItem {
  const _FazerCategoryItem({
    required this.categoryId,
    required this.name,
    required this.imageUrl,
    required this.offerCount,
    this.sortOrder = 999999,
  });

  final String categoryId;
  final String name;
  final String imageUrl;
  final int offerCount;
  final int sortOrder;

  _FazerCategoryItem copyWith({
    String? imageUrl,
    int? offerCount,
    int? sortOrder,
  }) {
    return _FazerCategoryItem(
      categoryId: categoryId,
      name: name,
      imageUrl: imageUrl ?? this.imageUrl,
      offerCount: offerCount ?? this.offerCount,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

class _GameKeysCategoriesView extends StatefulWidget {
  const _GameKeysCategoriesView({
    required this.categories,
    required this.onGameSelected,
  });

  final List<FazerCategory> categories;
  final ValueChanged<String> onGameSelected;

  @override
  State<_GameKeysCategoriesView> createState() => _GameKeysCategoriesViewState();
}

class _GameKeysCategoriesViewState extends State<_GameKeysCategoriesView> {
  String _query = '';
  String? _region;
  String? _platform;
  bool _favoritesOnly = false;
  bool _syncing = false;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    if (widget.categories.isEmpty) {
      unawaited(_syncFromFazer());
    }
  }

  @override
  void didUpdateWidget(covariant _GameKeysCategoriesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categories.isEmpty &&
        widget.categories.isEmpty &&
        !_syncing &&
        _syncError == null) {
      unawaited(_syncFromFazer());
    }
  }

  Future<void> _syncFromFazer() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      await _fazerService.syncGameKeyCategories();
    } catch (e) {
      if (mounted) setState(() => _syncError = '$e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.select((AuthProvider a) => a.user?.id);
    final all = widget.categories;

    if (_syncing && all.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('جاري جلب الألعاب...'),
          ],
        ),
      );
    }

    if (_syncError != null && all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_syncError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _syncFromFazer,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final regions = all
        .map((g) => g.region.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final platforms = all
        .map((g) => g.platform.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return StreamBuilder<Set<String>>(
      stream: uid == null
          ? Stream.value(const <String>{})
          : _fazerService.watchGameKeyFavorites(uid),
      builder: (context, favSnap) {
        final favorites = favSnap.data ?? const <String>{};
        final q = _query.trim().toLowerCase();
        final games = all.where((g) {
          if (_favoritesOnly && !favorites.contains(g.id)) return false;
          if (_region != null && g.region != _region) return false;
          if (_platform != null && g.platform != _platform) return false;
          if (q.isEmpty) return true;
          return g.name.toLowerCase().contains(q) ||
              g.platform.toLowerCase().contains(q) ||
              g.region.toLowerCase().contains(q);
        }).toList()
          ..sort((a, b) {
            final aFav = favorites.contains(a.id);
            final bFav = favorites.contains(b.id);
            if (aFav != bFav) return aFav ? -1 : 1;
            final byOrder = a.sortOrder.compareTo(b.sortOrder);
            return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
          });

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey('region-$_region'),
                      initialValue: _region,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'الدولة',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('كل الدول'),
                        ),
                        ...regions.map(
                          (r) => DropdownMenuItem<String?>(
                            value: r,
                            child: Text(r),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _region = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey('platform-$_platform'),
                      initialValue: _platform,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'المنصة',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('كل المنصات'),
                        ),
                        ...platforms.map(
                          (p) => DropdownMenuItem<String?>(
                            value: p,
                            child: Text(p),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _platform = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'المفضلة',
                    isSelected: _favoritesOnly,
                    onPressed: () =>
                        setState(() => _favoritesOnly = !_favoritesOnly),
                    icon: Icon(
                      _favoritesOnly ? Icons.star : Icons.star_border,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: _favoritesOnly
                          ? AppColors.primary
                          : AppColors.chipBg,
                      foregroundColor: _favoritesOnly
                          ? Colors.white
                          : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'بحث عن لعبة...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: games.isEmpty
                  ? Center(
                      child: Text(
                        _favoritesOnly
                            ? 'لا توجد ألعاب في المفضلة'
                            : all.isEmpty
                                ? 'لا توجد ألعاب بعد'
                                : 'لا توجد ألعاب مطابقة للفلاتر',
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.62,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: games.length,
                      itemBuilder: (context, index) {
                        final game = games[index];
                        final isFav = favorites.contains(game.id);
                        return _GameCoverTile(
                          game: game,
                          isFavorite: isFav,
                          onTap: () => widget.onGameSelected(game.id),
                          onFavoriteTap: uid == null
                              ? null
                              : () => _fazerService.setGameKeyFavorite(
                                    uid: uid,
                                    gameId: game.id,
                                    favorite: !isFav,
                                  ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _GameCoverTile extends StatelessWidget {
  const _GameCoverTile({
    required this.game,
    required this.onTap,
    this.isFavorite = false,
    this.onFavoriteTap,
  });

  final FazerCategory game;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    final cover = game.coverUrl;
    final badge = [
      if (game.platform.isNotEmpty) game.platform,
      if (game.region.isNotEmpty) game.region,
    ].join(' · ');

    return RepaintBoundary(
      child: Material(
        color: const Color(0xFF12161C),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.35),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cover.isEmpty)
                const ColoredBox(
                  color: Color(0xFF1C2430),
                  child: Icon(
                    Icons.videogame_asset_outlined,
                    color: Colors.white54,
                    size: 36,
                  ),
                )
              else
                AppNetworkImage(
                  url: cover,
                  fit: BoxFit.cover,
                  fallbackIcon: Icons.videogame_asset_outlined,
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Color(0xCC0B1016),
                    ],
                    stops: [0, 0.45, 1],
                  ),
                ),
              ),
              Positioned(
                top: 4,
                left: 4,
                right: 4,
                child: Row(
                  children: [
                    if (badge.isNotEmpty)
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    if (onFavoriteTap != null)
                      Material(
                        color: Colors.black45,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onFavoriteTap,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              isFavorite ? Icons.star : Icons.star_border,
                              size: 16,
                              color: isFavorite
                                  ? AppColors.accent
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 8,
                child: Text(
                  game.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _GameKeySkuList extends StatefulWidget {
  const _GameKeySkuList({
    required this.categoryId,
    required this.offers,
    required this.onBuy,
    required this.saleRate,
    this.fazerBalanceUsd,
  });

  final String categoryId;
  final List<FazerOffer> offers;
  final ValueChanged<FazerOffer> onBuy;
  final double saleRate;
  final double? fazerBalanceUsd;

  @override
  State<_GameKeySkuList> createState() => _GameKeySkuListState();
}

class _GameKeySkuListState extends State<_GameKeySkuList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final offers = widget.offers.where((o) {
      if (q.isEmpty) return true;
      return o.displayTitle.toLowerCase().contains(q) ||
          o.name.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.priceUsd.compareTo(b.priceUsd));

    return StreamBuilder<List<FazerCategory>>(
      stream: _fazerService.watchGameKeyCategories(),
      builder: (context, snap) {
        final game = (snap.data ?? const <FazerCategory>[])
            .where((g) => g.id == widget.categoryId)
            .cast<FazerCategory?>()
            .followedBy(const [null])
            .first;
        final cover = game?.coverUrl ??
            (offers.isNotEmpty ? offers.first.imageUrl : '');

        return Column(
          children: [
            if (cover.isNotEmpty)
              SizedBox(
                height: 160,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppNetworkImage(url: cover, fit: BoxFit.cover),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xDD0B1016)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 12,
                      child: Text(
                        game?.name ??
                            (offers.isNotEmpty
                                ? offers.first.categoryName
                                : ''),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'بحث عن إصدار...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: offers.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: offers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final offer = offers[index];
                        final outOfFazerBalance =
                            !offer.fazerBalanceCovers(widget.fazerBalanceUsd);
                        return Opacity(
                          opacity: outOfFazerBalance ? 0.55 : 1,
                          child: Material(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: outOfFazerBalance
                                  ? null
                                  : () => widget.onBuy(offer),
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  title: Text(
                                    offer.name.isEmpty
                                        ? offer.displayTitle
                                        : offer.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      if (game?.platform.isNotEmpty == true)
                                        game!.platform,
                                      if (game?.region.isNotEmpty == true)
                                        game!.region,
                                      if (offer.stock > 0)
                                        'المخزون: ${offer.stock}',
                                      if (outOfFazerBalance) 'نفذ',
                                    ].join(' · '),
                                  ),
                                  trailing: outOfFazerBalance
                                      ? const Text(
                                          'نفذ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.textSecondary,
                                          ),
                                        )
                                      : Text(
                                          Formatters.money(
                                            offer.gameKeyIqdPrice(
                                              widget.saleRate,
                                            ),
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.accentDark,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _FazerTopupCategoriesView extends StatefulWidget {
  const _FazerTopupCategoriesView({
    required this.categories,
    required this.onCategorySelected,
  });

  final List<FazerCategory> categories;
  final ValueChanged<String> onCategorySelected;

  @override
  State<_FazerTopupCategoriesView> createState() =>
      _FazerTopupCategoriesViewState();
}

class _FazerTopupCategoriesViewState extends State<_FazerTopupCategoriesView> {
  String _query = '';
  bool _favoritesOnly = false;
  bool _syncing = false;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    if (widget.categories.isEmpty) {
      unawaited(_syncFromFazer());
    }
  }

  @override
  void didUpdateWidget(covariant _FazerTopupCategoriesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categories.isEmpty &&
        widget.categories.isEmpty &&
        !_syncing &&
        _syncError == null) {
      unawaited(_syncFromFazer());
    }
  }

  Future<void> _syncFromFazer() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      await _fazerService.syncTopupCategories();
    } catch (e) {
      if (mounted) setState(() => _syncError = '$e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.select((AuthProvider a) => a.user?.id);
    final all = widget.categories;

    if (_syncing && all.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('جاري جلب ألعاب الشحن...'),
          ],
        ),
      );
    }

    if (_syncError != null && all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_syncError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _syncFromFazer,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<Set<String>>(
      stream: uid == null
          ? Stream.value(const <String>{})
          : _fazerService.watchTopupFavorites(uid),
      builder: (context, favSnap) {
        final favorites = favSnap.data ?? const <String>{};
        final q = _query.trim().toLowerCase();
        final games = all.where((g) {
          if (_favoritesOnly && !favorites.contains(g.id)) return false;
          if (q.isEmpty) return true;
          return g.name.toLowerCase().contains(q);
        }).toList()
          ..sort((a, b) {
            final aFav = favorites.contains(a.id);
            final bFav = favorites.contains(b.id);
            if (aFav != bFav) return aFav ? -1 : 1;
            final byOrder = a.sortOrder.compareTo(b.sortOrder);
            return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
          });

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'بحث عن لعبة...',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'المفضلة',
                    isSelected: _favoritesOnly,
                    onPressed: () =>
                        setState(() => _favoritesOnly = !_favoritesOnly),
                    icon: Icon(
                      _favoritesOnly ? Icons.star : Icons.star_border,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: _favoritesOnly
                          ? AppColors.primary
                          : AppColors.chipBg,
                      foregroundColor: _favoritesOnly
                          ? Colors.white
                          : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: games.isEmpty
                  ? Center(
                      child: Text(
                        _favoritesOnly
                            ? 'لا توجد ألعاب في المفضلة'
                            : all.isEmpty
                                ? 'لا توجد ألعاب شحن بعد'
                                : 'لا توجد ألعاب مطابقة للبحث',
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.62,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: games.length,
                      itemBuilder: (context, index) {
                        final game = games[index];
                        final isFav = favorites.contains(game.id);
                        return _GameCoverTile(
                          game: game,
                          isFavorite: isFav,
                          onTap: () => widget.onCategorySelected(game.id),
                          onFavoriteTap: uid == null
                              ? null
                              : () => _fazerService.setTopupFavorite(
                                    uid: uid,
                                    categoryId: game.id,
                                    favorite: !isFav,
                                  ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _FazerTopupOffersBody extends StatefulWidget {
  const _FazerTopupOffersBody({
    super.key,
    required this.categoryId,
    required this.onBuy,
    required this.saleRate,
    this.fazerBalanceUsd,
  });

  final String categoryId;
  final ValueChanged<FazerOffer> onBuy;
  final double saleRate;
  final double? fazerBalanceUsd;

  @override
  State<_FazerTopupOffersBody> createState() => _FazerTopupOffersBodyState();
}

class _FazerTopupOffersBodyState extends State<_FazerTopupOffersBody> {
  String? _syncError;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _FazerTopupOffersBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId) {
      _sync();
    }
  }

  Future<void> _sync() async {
    setState(() => _syncError = null);
    try {
      await _fazerService.syncCategoryOffers(widget.categoryId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FazerOffer>>(
      stream: _fazerService.watchOffersForCategory(widget.categoryId),
      builder: (context, snap) {
        final offers = (snap.data ?? const <FazerOffer>[])
            .where((o) => o.isTopup)
            .toList()
          ..sort((a, b) => a.priceUsd.compareTo(b.priceUsd));
        if (offers.isEmpty && _syncError != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_syncError!, textAlign: TextAlign.center),
            ),
          );
        }
        if (offers.isEmpty && snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return _FazerCategoryOffersView(
          categoryId: widget.categoryId,
          offers: offers,
          onBuy: widget.onBuy,
          fazerBalanceUsd: widget.fazerBalanceUsd,
          priceOf: (offer) => offer.gameKeyIqdPrice(widget.saleRate),
          searchHint: 'بحث سريع عن شحنة...',
        );
      },
    );
  }
}

class _FazerWorldCategoriesView extends StatelessWidget {
  const _FazerWorldCategoriesView({
    required this.giftCategories,
    required this.pricedCategoryIds,
    required this.onCategorySelected,
  });

  final List<FazerCategory> giftCategories;
  final Set<String> pricedCategoryIds;
  final ValueChanged<String> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    final items = giftCategories
        .where((c) => !pricedCategoryIds.contains(c.id))
        .map(
          (c) => _FazerCategoryItem(
            categoryId: c.id,
            name: c.name.isEmpty ? c.id : c.name,
            imageUrl: c.coverUrl,
            offerCount: 0,
            sortOrder: c.sortOrder,
          ),
        )
        .toList()
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
      });

    return _FazerNamedGrid(
      items: items,
      searchHint: 'بحث سريع عن فئة...',
      emptyText: 'لا توجد بطاقات عالمية بعد. زامن البطاقات أولاً',
      fallbackIcon: Icons.public_outlined,
      onSelected: onCategorySelected,
    );
  }
}

class _FazerWorldOffersBody extends StatefulWidget {
  const _FazerWorldOffersBody({
    super.key,
    required this.categoryId,
    required this.onBuy,
    required this.saleRate,
    this.fazerBalanceUsd,
  });

  final String categoryId;
  final ValueChanged<FazerOffer> onBuy;
  final double saleRate;
  final double? fazerBalanceUsd;

  @override
  State<_FazerWorldOffersBody> createState() => _FazerWorldOffersBodyState();
}

class _FazerWorldOffersBodyState extends State<_FazerWorldOffersBody> {
  String? _syncError;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _FazerWorldOffersBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId) {
      _sync();
    }
  }

  Future<void> _sync() async {
    setState(() => _syncError = null);
    try {
      await _fazerService.syncCategoryOffers(widget.categoryId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FazerOffer>>(
      stream: _fazerService.watchOffersForCategory(widget.categoryId),
      builder: (context, snap) {
        final offers = (snap.data ?? const <FazerOffer>[])
            .where((o) => !o.isGameKey && !o.isPriced)
            .toList()
          ..sort((a, b) => a.priceUsd.compareTo(b.priceUsd));
        if (offers.isEmpty && _syncError != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_syncError!, textAlign: TextAlign.center),
            ),
          );
        }
        if (offers.isEmpty && snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return _FazerCategoryOffersView(
          categoryId: widget.categoryId,
          offers: offers,
          onBuy: widget.onBuy,
          fazerBalanceUsd: widget.fazerBalanceUsd,
          priceOf: (offer) => offer.gameKeyIqdPrice(widget.saleRate),
          searchHint: 'بحث سريع عن بطاقة...',
        );
      },
    );
  }
}

class _GameKeyOffersBody extends StatefulWidget {
  const _GameKeyOffersBody({
    super.key,
    required this.categoryId,
    required this.onBuy,
    required this.saleRate,
    this.fazerBalanceUsd,
  });

  final String categoryId;
  final ValueChanged<FazerOffer> onBuy;
  final double saleRate;
  final double? fazerBalanceUsd;

  @override
  State<_GameKeyOffersBody> createState() => _GameKeyOffersBodyState();
}

class _GameKeyOffersBodyState extends State<_GameKeyOffersBody> {
  String? _syncError;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _GameKeyOffersBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId) {
      _sync();
    }
  }

  Future<void> _sync() async {
    setState(() => _syncError = null);
    try {
      await _fazerService.syncCategoryOffers(widget.categoryId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FazerOffer>>(
      stream: _fazerService.watchOffersForCategory(widget.categoryId),
      builder: (context, snap) {
        final offers = snap.data ?? const <FazerOffer>[];
        if (offers.isEmpty && _syncError != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_syncError!, textAlign: TextAlign.center),
            ),
          );
        }
        return _GameKeySkuList(
          categoryId: widget.categoryId,
          offers: offers,
          onBuy: widget.onBuy,
          saleRate: widget.saleRate,
          fazerBalanceUsd: widget.fazerBalanceUsd,
        );
      },
    );
  }
}

class _FazerNamedGrid extends StatefulWidget {
  const _FazerNamedGrid({
    required this.items,
    required this.searchHint,
    required this.emptyText,
    required this.fallbackIcon,
    required this.onSelected,
  });

  final List<_FazerCategoryItem> items;
  final String searchHint;
  final String emptyText;
  final IconData fallbackIcon;
  final ValueChanged<String> onSelected;

  @override
  State<_FazerNamedGrid> createState() => _FazerNamedGridState();
}

class _FazerNamedGridState extends State<_FazerNamedGrid> {
  String _query = '';

  List<_FazerCategoryItem> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = List<_FazerCategoryItem>.from(widget.items)
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
      });
    if (q.isEmpty) return list;
    return list.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cats = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Autocomplete<String>(
            optionsBuilder: (textEditingValue) {
              final q = textEditingValue.text.trim().toLowerCase();
              final names = widget.items.map((c) => c.name).toSet().toList()
                ..sort();
              if (q.isEmpty) return names.take(8);
              return names.where((n) => n.toLowerCase().contains(q)).take(10);
            },
            onSelected: (value) => setState(() => _query = value),
            fieldViewBuilder: (context, controller, focusNode, onSubmit) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: (v) => setState(() => _query = v),
                onSubmitted: (_) => onSubmit(),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              final opts = options.toList();
              if (opts.isEmpty) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.topRight,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 220,
                      maxWidth: 420,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: opts.length,
                      itemBuilder: (context, index) {
                        final option = opts[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            option,
                            style: const TextStyle(fontSize: 13),
                          ),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: cats.isEmpty
              ? Center(child: Text(widget.emptyText))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.05,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: cats.length,
                  itemBuilder: (context, index) {
                    final cat = cats[index];
                    return _CompanyTile(
                      name: cat.name,
                      imageUrl: cat.imageUrl,
                      fallbackIcon: widget.fallbackIcon,
                      onTap: () => widget.onSelected(cat.categoryId),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FazerCategoryOffersView extends StatefulWidget {
  const _FazerCategoryOffersView({
    super.key,
    required this.categoryId,
    required this.offers,
    required this.onBuy,
    this.priceOf,
    this.fazerBalanceUsd,
    this.searchHint = 'بحث سريع عن بطاقة...',
  });

  final String categoryId;
  final List<FazerOffer> offers;
  final ValueChanged<FazerOffer> onBuy;
  final double Function(FazerOffer offer)? priceOf;
  final double? fazerBalanceUsd;
  final String searchHint;

  @override
  State<_FazerCategoryOffersView> createState() =>
      _FazerCategoryOffersViewState();
}

class _FazerCategoryOffersViewState extends State<_FazerCategoryOffersView> {
  String _query = '';

  List<FazerOffer> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.offers;
    return widget.offers.where((o) {
      return o.displayTitle.toLowerCase().contains(q) ||
          o.name.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final offers = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Autocomplete<String>(
            optionsBuilder: (textEditingValue) {
              final q = textEditingValue.text.trim().toLowerCase();
              final titles = widget.offers.map((o) => o.displayTitle).toSet().toList()
                ..sort();
              if (q.isEmpty) return titles.take(8);
              return titles.where((t) => t.toLowerCase().contains(q)).take(10);
            },
            onSelected: (value) => setState(() => _query = value),
            fieldViewBuilder: (context, controller, focusNode, onSubmit) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: (v) => setState(() => _query = v),
                onSubmitted: (_) => onSubmit(),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              final opts = options.toList();
              if (opts.isEmpty) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.topRight,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 220,
                      maxWidth: 420,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: opts.length,
                      itemBuilder: (context, index) {
                        final option = opts[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            option,
                            style: const TextStyle(fontSize: 13),
                          ),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: offers.isEmpty
              ? const Center(child: Text('لا توجد بطاقات مطابقة للبحث'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: offers.length,
                  itemBuilder: (context, index) {
                    final offer = offers[index];
                    final product = Product(
                      id: offer.id,
                      companyId: widget.categoryId,
                      name: offer.displayTitle,
                      imageUrl: offer.imageUrl,
                      price: widget.priceOf?.call(offer) ??
                          offer.kushkPrice ??
                          0,
                      hasOffer: false,
                      isActive: true,
                      buttonColorHex: '#C9A227',
                      buttonText: 'شراء',
                      sortOrder: index,
                      stockCount: offer.fazerDisplayStock(widget.fazerBalanceUsd),
                    );
                    return RepaintBoundary(
                      child: ProductCardWidget(
                        product: product,
                        companyLogo: offer.imageUrl,
                        soldOutText: 'نفذ',
                        onBuy: () => widget.onBuy(offer),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PricedProductsBody extends StatelessWidget {
  const _PricedProductsBody({
    required this.company,
    required this.userId,
    required this.onSearch,
    required this.onBuy,
  });

  final Company company;
  final String? userId;
  final ValueChanged<String> onSearch;
  final ValueChanged<Product> onBuy;

  @override
  Widget build(BuildContext context) {
    final products = context.select((CatalogProvider c) => c.filteredProducts);

    return StreamBuilder<Map<String, UserCustomPrice>>(
      stream: userId == null
          ? Stream.value(const <String, UserCustomPrice>{})
          : _storeCustomPrices.watchForUser(userId!),
      builder: (context, pricesSnap) {
        final customs = pricesSnap.data ?? const <String, UserCustomPrice>{};
        final priced = products
            .map((p) => productWithCustomPrice(p, customs[p.id]))
            .toList();

        return _ProductsView(
          company: company,
          products: priced,
          onSearch: onSearch,
          onBuy: onBuy,
        );
      },
    );
  }
}

class _CompanyShortcutsBar extends StatelessWidget {
  const _CompanyShortcutsBar({
    required this.companies,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Company> companies;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: companies.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final company = companies[index];
          final selected = company.id == selectedId;
          return ChoiceChip(
            label: Text(company.name),
            selected: selected,
            onSelected: (_) => onSelected(selected ? null : company.id),
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}

class _ProductsView extends StatefulWidget {
  const _ProductsView({
    required this.company,
    required this.products,
    required this.onSearch,
    required this.onBuy,
  });

  final Company company;
  final List<Product> products;
  final ValueChanged<String> onSearch;
  final ValueChanged<Product> onBuy;

  @override
  State<_ProductsView> createState() => _ProductsViewState();
}

class _ProductsViewState extends State<_ProductsView> {
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      widget.onSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'ابحث عن فئة كارت...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: widget.products.isEmpty
              ? const Center(child: Text('لا توجد كروت لهذه الشركة حالياً'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.82,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: widget.products.length,
                  itemBuilder: (context, index) {
                    final product = widget.products[index];
                    return RepaintBoundary(
                      child: ProductCardWidget(
                        product: product,
                        companyLogo: widget.company.logoUrl,
                        onBuy: () => widget.onBuy(product),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TopupFieldsDialog extends StatefulWidget {
  const _TopupFieldsDialog({
    required this.categoryId,
    required this.categoryName,
    required this.fields,
    required this.requiresValidate,
  });

  final String categoryId;
  final String categoryName;
  final List<FazerBuyerField> fields;
  final bool requiresValidate;

  @override
  State<_TopupFieldsDialog> createState() => _TopupFieldsDialogState();
}

class _TopupFieldsDialogState extends State<_TopupFieldsDialog> {
  late final Map<String, TextEditingController> _controllers;
  final _selected = <String, String>{};
  String? _playerName;
  var _validating = false;
  var _error = '';

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final f in widget.fields)
        if (!f.isSelect) f.key: TextEditingController(),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String>? _collect() {
    final values = <String, String>{};
    for (final f in widget.fields) {
      final v = f.isSelect
          ? (_selected[f.key] ?? '').trim()
          : (_controllers[f.key]?.text ?? '').trim();
      if (v.isEmpty) {
        setState(() => _error = 'أكمل جميع الحقول');
        return null;
      }
      values[f.key] = v;
    }
    return values;
  }

  Future<void> _validate() async {
    final values = _collect();
    if (values == null) return;
    setState(() {
      _validating = true;
      _error = '';
      _playerName = null;
    });
    try {
      final data = await _fazerService.validateTopupId(
        categoryId: widget.categoryId,
        fields: values,
      );
      if (!mounted) return;
      final valid = data['valid'] == true;
      final name = data['playerName']?.toString() ?? '';
      if (!valid) {
        setState(() {
          _validating = false;
          _error = 'معرّف اللاعب غير صالح';
        });
        return;
      }
      setState(() {
        _validating = false;
        _playerName = name.isEmpty ? 'تم التحقق' : name;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _validating = false;
        _error = '$e';
      });
    }
  }

  String? _fieldHint(FazerBuyerField field) {
    final key = field.key.toLowerCase();
    final label = field.label.toLowerCase();
    if (_isServerField(field)) {
      return 'رقم/اسم السيرفر كما يظهر في اللعبة';
    }
    if (key.contains('player') || label.contains('id')) {
      return 'معرّف اللاعب من داخل اللعبة';
    }
    return null;
  }

  bool _isServerField(FazerBuyerField field) {
    final key = field.key.toLowerCase();
    final label = field.label.toLowerCase();
    return key.contains('zone') ||
        key.contains('server') ||
        label.contains('server') ||
        label.contains('سرف');
  }

  static const _serverFieldHelpText =
      'يرجى الحصول على سرفر ID من داخل اللعبة في ملفك الشخصي';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.categoryName.isEmpty ? 'بيانات اللاعب' : widget.categoryName,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.fields.length > 1)
              const Text(
                'الحقول التالية حسب متطلبات اللعبة',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            if (widget.fields.length > 1) const SizedBox(height: 8),
            for (final f in widget.fields) ...[
              if (f.isSelect)
                DropdownButtonFormField<String>(
                  key: ValueKey('select-${f.key}-${_selected[f.key]}'),
                  initialValue: _selected[f.key],
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: f.label,
                    helperText:
                        _isServerField(f) ? _serverFieldHelpText : 'اختر من القائمة',
                    isDense: true,
                  ),
                  items: f.options
                      .map(
                        (o) => DropdownMenuItem<String>(
                          value: o.value,
                          child: Text(o.label),
                        ),
                      )
                      .toList(),
                  onChanged: _validating
                      ? null
                      : (v) => setState(() {
                            _selected[f.key] = v ?? '';
                            _error = '';
                          }),
                )
              else
                TextField(
                  controller: _controllers[f.key],
                  autofocus: f.key == widget.fields.first.key,
                  decoration: InputDecoration(
                    labelText: f.label,
                    hintText: _fieldHint(f),
                    helperText:
                        _isServerField(f) ? _serverFieldHelpText : null,
                    isDense: true,
                  ),
                  onChanged: (_) {
                    if (_error.isNotEmpty) setState(() => _error = '');
                  },
                ),
              const SizedBox(height: 10),
            ],
            if (_playerName != null)
              Text(
                'اللاعب: $_playerName',
                style: const TextStyle(
                  color: AppColors.accentDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (_error.isNotEmpty)
              Text(_error, style: const TextStyle(color: AppColors.danger)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _validating ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        if (widget.requiresValidate && _playerName == null)
          FilledButton(
            onPressed: _validating ? null : _validate,
            child: _validating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('تحقق'),
          ),
        FilledButton(
          onPressed: _validating
              ? null
              : () {
                  final values = _collect();
                  if (values == null) return;
                  if (widget.requiresValidate && _playerName == null) {
                    setState(() => _error = 'تحقق من معرّف اللاعب أولاً');
                    return;
                  }
                  Navigator.pop(context, values);
                },
          child: const Text('متابعة'),
        ),
      ],
    );
  }
}

class _TelegramUsernameDialog extends StatefulWidget {
  const _TelegramUsernameDialog();

  @override
  State<_TelegramUsernameDialog> createState() => _TelegramUsernameDialogState();
}

class _TelegramUsernameDialogState extends State<_TelegramUsernameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim().replaceFirst(RegExp(r'^@+'), '');
    if (v.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل يوزرنيم صالحاً')),
      );
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('يوزرنيم تيليجرام'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'مثال: username بدون @',
          prefixText: '@',
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('متابعة'),
        ),
      ],
    );
  }
}
