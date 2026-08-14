import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/catalog_models.dart';
import '../services/catalog_service.dart';

class CatalogProvider extends ChangeNotifier {
  CatalogProvider(this._service) {
    _service.ensureAllSpecialCompanies();
    _subs.add(_service.watchCompanies().listen((v) {
      companies = v;
      companiesLoaded = true;
      notifyListeners();
    }));
  }

  final CatalogService _service;
  final List<StreamSubscription> _subs = [];
  StreamSubscription? _productsSub;
  String? _productsCompanyId;

  List<Company> companies = [];
  List<Product> products = [];
  String? selectedCompanyId;
  String searchQuery = '';
  bool companiesLoaded = false;

  List<Product> get filteredProducts {
    final q = searchQuery.trim();
    if (q.isEmpty) return products;
    return products.where((p) => p.name.contains(q)).toList();
  }

  Company? companyOf(String id) {
    try {
      return companies.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  void selectCompany(String? id) {
    selectedCompanyId = id;
    searchQuery = '';
    _bindProducts(id);
    notifyListeners();
  }

  void search(String value) {
    if (searchQuery == value) return;
    searchQuery = value;
    notifyListeners();
  }

  void _bindProducts(String? companyId) {
    if (companyId == null ||
        companyId.isEmpty ||
        companyId == kFazerAllCompanyId ||
        companyId == kFazerGameKeysCompanyId ||
        companyId == kFazerWorldCompanyId ||
        companyId == kFazerTopupsCompanyId ||
        companyId.startsWith('fazer:') ||
        companyId.startsWith(kFazerGkPrefix) ||
        companyId.startsWith(kFazerWorldPrefix) ||
        companyId.startsWith(kFazerTopupPrefix)) {
      _productsSub?.cancel();
      _productsSub = null;
      _productsCompanyId = null;
      products = [];
      return;
    }
    if (_productsCompanyId == companyId && _productsSub != null) return;

    _productsSub?.cancel();
    _productsCompanyId = companyId;
    products = [];
    _productsSub = _service.watchProducts(companyId: companyId).listen((v) {
      products = v;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _productsSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
