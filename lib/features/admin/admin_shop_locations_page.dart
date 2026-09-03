import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../services/shop_location_service.dart';

class AdminShopLocationsPage extends StatefulWidget {
  const AdminShopLocationsPage({super.key});

  @override
  State<AdminShopLocationsPage> createState() => _AdminShopLocationsPageState();
}

class _AdminShopLocationsPageState extends State<AdminShopLocationsPage> {
  final _service = ShopLocationService();
  final _mapController = MapController();
  String _lastFitKey = '';
  String _searchQuery = '';

  static const _iraqCenter = LatLng(33.3152, 44.3661);

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  List<_ShopPin> _pinsFrom(QuerySnapshot<Map<String, dynamic>> snap) {
    final pins = <_ShopPin>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final lat = (d['locationLat'] as num?)?.toDouble();
      final lng = (d['locationLng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
      final shopName = (d['shopName']?.toString().trim().isNotEmpty == true)
          ? d['shopName'].toString().trim()
          : (d['name']?.toString().trim().isNotEmpty == true
              ? d['name'].toString().trim()
              : 'محل بدون اسم');
      final ownerName = d['name']?.toString().trim() ?? '';
      pins.add(
        _ShopPin(
          id: doc.id,
          shopName: shopName,
          ownerName: ownerName,
          phone: d['phone']?.toString() ?? '',
          point: LatLng(lat, lng),
        ),
      );
    }
    return pins;
  }

  bool _matchesSearch(_ShopPin pin) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final qPhone = q.replaceAll(RegExp(r'[\s\-+()]'), '');
    final phone = pin.phone.replaceAll(RegExp(r'[\s\-+()]'), '');
    return pin.shopName.toLowerCase().contains(q) ||
        pin.ownerName.toLowerCase().contains(q) ||
        (qPhone.isNotEmpty && phone.contains(qPhone));
  }

  void _fitPinsIfNeeded(List<_ShopPin> pins) {
    final key = pins.map((p) => '${p.id}:${p.point.latitude},${p.point.longitude}').join('|');
    if (key == _lastFitKey) return;
    _lastFitKey = key;
    if (pins.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (pins.length == 1) {
        _mapController.move(pins.first.point, 15);
        return;
      }
      final bounds = LatLngBounds.fromPoints(pins.map((p) => p.point).toList());
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مواقع الزبائن')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _service.watchShopsWithLocation(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'تعذر تحميل المواقع: ${snapshot.error}',
                style: const TextStyle(color: AppColors.danger),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allPins = _pinsFrom(snapshot.data!);
          final pins = allPins.where(_matchesSearch).toList();
          _fitPinsIfNeeded(pins);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'بحث: اسم المتجر، المسؤول، أو الهاتف',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppColors.chipBg,
                child: Text(
                  _searchQuery.trim().isEmpty
                      ? (pins.isEmpty
                          ? 'لا توجد مواقع محفوظة بعد. تظهر هنا المحلات التي وافقت على صلاحية الموقع.'
                          : 'عدد المحلات على الخريطة: ${pins.length}')
                      : (pins.isEmpty
                          ? 'لا توجد نتائج مطابقة للبحث'
                          : 'نتائج البحث: ${pins.length} من ${allPins.length}'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: pins.isEmpty
                    ? const Center(child: Text('لا توجد مواقع للعرض'))
                    : FlutterMap(
                        mapController: _mapController,
                        options: const MapOptions(
                          initialCenter: _iraqCenter,
                          initialZoom: 6.2,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'dnz.dnzteam.Kushk',
                          ),
                          MarkerLayer(
                            markers: [
                              for (final pin in pins)
                                Marker(
                                  point: pin.point,
                                  width: 160,
                                  height: 70,
                                  alignment: Alignment.topCenter,
                                  child: Tooltip(
                                    message: [
                                      pin.shopName,
                                      if (pin.ownerName.isNotEmpty)
                                        pin.ownerName,
                                      if (pin.phone.isNotEmpty) pin.phone,
                                    ].join('\n'),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            boxShadow: AppColors.cardShadow,
                                          ),
                                          child: Text(
                                            pin.shopName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const Icon(
                                          Icons.location_on,
                                          color: AppColors.danger,
                                          size: 34,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ShopPin {
  const _ShopPin({
    required this.id,
    required this.shopName,
    required this.ownerName,
    required this.phone,
    required this.point,
  });

  final String id;
  final String shopName;
  final String ownerName;
  final String phone;
  final LatLng point;
}
