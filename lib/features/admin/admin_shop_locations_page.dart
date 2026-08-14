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
      pins.add(
        _ShopPin(
          id: doc.id,
          shopName: shopName,
          phone: d['phone']?.toString() ?? '',
          point: LatLng(lat, lng),
        ),
      );
    }
    return pins;
  }

  void _fitPinsIfNeeded(List<_ShopPin> pins) {
    final key = pins.map((p) => '${p.id}:${p.point.latitude},${p.point.longitude}').join('|');
    if (key == _lastFitKey) return;
    _lastFitKey = key;
    if (pins.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (pins.length == 1) {
        _mapController.move(pins.first.point, 14);
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

          final pins = _pinsFrom(snapshot.data!);
          _fitPinsIfNeeded(pins);

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppColors.chipBg,
                child: Text(
                  pins.isEmpty
                      ? 'لا توجد مواقع محفوظة بعد. تظهر هنا المحلات التي وافقت على صلاحية الموقع.'
                      : 'عدد المحلات على الخريطة: ${pins.length}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: FlutterMap(
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
                                      borderRadius: BorderRadius.circular(8),
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
    required this.phone,
    required this.point,
  });

  final String id;
  final String shopName;
  final String phone;
  final LatLng point;
}
