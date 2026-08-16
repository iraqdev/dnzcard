import 'package:flutter/material.dart';
import 'package:thermal_printer_flutter/thermal_printer_flutter.dart'
    show Printer;

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brief_print_spinner.dart';
import '../../printer/extended_printer_bridge.dart';
import '../../printer/generic_escpos_printer.dart';
import '../../printer/installed_printer_store.dart';
import '../../printer/mini_ble_printer.dart';
import '../../printer/paper_size.dart';
import '../../printer/printer_access_guard.dart';
import '../../printer/printer_discovery_service.dart';
import '../../printer/printer_engine_type.dart';
import '../../printer/printer_service.dart';
import '../../printer/printer_user_messages.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final _service = PrinterService();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '9100');

  String _status = '—';
  String _driver = 'AUTO';
  Map<String, dynamic> _info = {};
  List<Map<String, dynamic>> _devices = [];
  String? _selectedDeviceId;
  PaperSizeMm _paperSize = PaperSizeMm.mm58;
  PrinterEngineType _engine = PrinterEngineType.kushkNative;
  PrinterDiscoveryResult? _discovery;
  String? _btLabel;
  String? _miniBtLabel;
  bool _busy = false;

  static const drivers = [
    'AUTO',
    'CENTERM',
    'BLUETOOTH',
    'USB',
    'SUNMI',
    'IMIN',
    'PAX',
    'UROVO',
    'TELPO',
    'NEWLAND',
    'NETWORK',
    'ANDROID_PRINT',
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      _paperSize = await _service.loadPaperSize();
      _engine = await _service.loadEngine();
      _discovery = await InstalledPrinterStore.loadDiscoveryResult();
      _status = await _service.status();
      _info = await _service.detect();
      _driver = (_info['driver'] ?? _info['selectedDriver'] ?? _driver)
          .toString();
      if (_driver.isEmpty) _driver = 'AUTO';
      final rawMm = _info['paperSizeMm'];
      if (rawMm is num) {
        _paperSize = PaperSizeMm.fromMm(rawMm.toInt());
      }
      final rawDevices = _info['devices'];
      if (rawDevices is List) {
        _devices = rawDevices
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else {
        _devices = await _service.listDevices();
      }
      final network = await InstalledPrinterStore.loadNetworkPrinter();
      _hostController.text = network.host;
      _portController.text = network.port.toString();
      final btJson = await InstalledPrinterStore.loadBluetoothDeviceJson();
      _btLabel = (btJson != null && btJson.isNotEmpty)
          ? 'طابعة Bluetooth محفوظة'
          : null;
      final mini = await InstalledPrinterStore.loadMiniBleDevice();
      _miniBtLabel = mini == null ? null : 'Mini محفوظة: ${mini.name}';
    } catch (e) {
      _status = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rediscover() async {
    setState(() => _busy = true);
    try {
      await PrinterAccessGuard.requestWithExplanationIfNeeded(context);
      if (!mounted) return;
      final result = await PrinterDiscoveryService.discoverAndApply(
        respectManualEngine: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.recognized
                ? 'تم التعرف: ${result.displayName}'
                : PrinterUserMessages.unrecognized,
          ),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل البحث: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPaperSize(PaperSizeMm size) async {
    setState(() {
      _paperSize = size;
      _busy = true;
    });
    try {
      await _service.setPaperSize(size);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم ضبط قياس الورق على ${size.label}')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ القياس: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setEngine(PrinterEngineType engine) async {
    setState(() {
      _engine = engine;
      _busy = true;
    });
    try {
      await _service.setEngine(engine, manual: true);
      if (engine == PrinterEngineType.kushkNative) {
        await _service.setDriver('AUTO');
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setDriver(String value) async {
    setState(() {
      _driver = value;
      _busy = true;
    });
    try {
      await _service.setEngine(PrinterEngineType.kushkNative, manual: true);
      await _service.setDriverWithDevice(
        driver: value,
        address: _selectedDeviceId,
        id: _selectedDeviceId,
      );
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectDevice(Map<String, dynamic> device) async {
    final id = (device['id'] ?? device['address'] ?? '').toString();
    final type = (device['type'] ?? 'BLUETOOTH').toString().toUpperCase();
    setState(() {
      _selectedDeviceId = id;
      _driver = type;
      _busy = true;
    });
    try {
      await _service.setEngine(PrinterEngineType.kushkNative, manual: true);
      await _service.setDriverWithDevice(
        driver: type,
        address: id,
        id: id,
      );
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم اختيار: ${device['name'] ?? id}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الاتصال: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickBluetooth() async {
    setState(() => _busy = true);
    try {
      final printers = await ExtendedPrinterBridge.scanBluetoothPrinters();
      if (!mounted) return;
      if (printers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لم يُعثر على طابعات Bluetooth. تأكد من الاقتران.'),
          ),
        );
        return;
      }
      final picked = await showDialog<Printer>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('اختر طابعة Bluetooth'),
          children: printers
              .map(
                (p) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, p),
                  child: Text(p.name),
                ),
              )
              .toList(),
        ),
      );
      if (picked == null) return;
      await InstalledPrinterStore.saveBluetoothDeviceJson(picked.toJson());
      await _service.setEngine(PrinterEngineType.bluetoothV1, manual: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ: ${picked.name}')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(PrinterUserMessages.forPrintError(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickMiniBluetooth() async {
    setState(() => _busy = true);
    try {
      final printers = await MiniBlePrinter.scan();
      if (!mounted) return;
      if (printers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'لم يُعثر على طابعة Mini. شغّل الطابعة وفعّل البلوتوث ثم أعد المحاولة.',
            ),
          ),
        );
        return;
      }
      final picked = await showDialog<MiniBleDeviceInfo>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('اختر طابعة Mini'),
          children: printers
              .map(
                (p) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, p),
                  child: Text('${p.name}\n${p.remoteId}'),
                ),
              )
              .toList(),
        ),
      );
      if (picked == null) return;
      await InstalledPrinterStore.saveMiniBleDevice(picked);
      await _service.setEngine(PrinterEngineType.bluetoothMini, manual: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ Mini: ${picked.name}')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(PrinterUserMessages.forPrintError(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveNetwork() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 9100;
    await InstalledPrinterStore.saveNetworkPrinter(host: host, port: port);
    await _service.setEngine(PrinterEngineType.network, manual: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ إعدادات طابعة الشبكة')),
    );
  }

  Future<void> _requestUsb() async {
    setState(() => _busy = true);
    try {
      final has = await GenericEscPosPrinter.hasUsbPrinter();
      if (!has) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(PrinterUserMessages.forPrintError('USB_PRINTER_NOT_FOUND')),
          ),
        );
        return;
      }
      final granted = await GenericEscPosPrinter.requestUsbPermission();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted ? 'تم منح صلاحية USB' : 'لم تُمنح صلاحية USB',
          ),
        ),
      );
      if (granted) {
        await _service.setEngine(PrinterEngineType.usb, manual: true);
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    final dismissSpinner = showBriefPrintSpinner(context);
    try {
      await _service.testPrint(context: context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إرسال طباعة اختبارية (${_paperSize.label} · ${_engine.label})',
          ),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(PrinterUserMessages.forPrintError(e))),
      );
    } finally {
      dismissSpinner();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final discovery = _discovery;
    final recognized = discovery?.recognized == true;

    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الطابعة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الحالة', style: TextStyle(color: Colors.white70)),
                Text(
                  _busy ? 'جاري الفحص...' : _status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'الجهاز: ${_info['manufacturer'] ?? '-'} / ${_info['model'] ?? '-'}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  'الورق: ${_paperSize.label} (${_paperSize.dots} نقطة)',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  'المحرك: ${_engine.label}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: recognized
                  ? Colors.green.withValues(alpha: 0.08)
                  : Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: recognized ? Colors.green : Colors.orange,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recognized
                      ? 'تم التعرف على الطابعة'
                      : PrinterUserMessages.unrecognized,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: recognized ? Colors.green.shade800 : Colors.orange.shade900,
                  ),
                ),
                if (discovery != null) ...[
                  const SizedBox(height: 6),
                  Text(discovery.displayName),
                  if (discovery.recognized)
                    Text(
                      'المصدر: ${discovery.source} · ورق ${discovery.paperMm}mm',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _rediscover,
            icon: const Icon(Icons.search),
            label: const Text('إعادة البحث عن الطابعة'),
          ),
          const SizedBox(height: 16),
          const Text(
            'قياس الورق',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PaperSizeMm.values
                .map(
                  (size) => ChoiceChip(
                    label: Text(size.label),
                    selected: _paperSize == size,
                    onSelected: _busy ? null : (_) => _setPaperSize(size),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text(
            'نوع الطابعة',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...PrinterEngineType.values.map(
            (engine) => ListTile(
              title: Text(engine.label),
              subtitle: Text(engine.description),
              leading: Icon(
                _engine == engine
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: _engine == engine ? AppColors.primary : null,
              ),
              onTap: _busy ? null : () => _setEngine(engine),
            ),
          ),
          if (_engine == PrinterEngineType.bluetoothV1) ...[
            const SizedBox(height: 8),
            if (_btLabel != null)
              Text(_btLabel!, style: const TextStyle(color: AppColors.textSecondary)),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _pickBluetooth,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('اختيار طابعة Bluetooth'),
            ),
          ],
          if (_engine == PrinterEngineType.bluetoothMini) ...[
            const SizedBox(height: 8),
            if (_miniBtLabel != null)
              Text(
                _miniBtLabel!,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _pickMiniBluetooth,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('اختيار طابعة Mini'),
            ),
          ],
          if (_engine == PrinterEngineType.usb) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _requestUsb,
              icon: const Icon(Icons.usb),
              label: const Text('السماح بطابعة USB'),
            ),
          ],
          if (_engine == PrinterEngineType.network) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'عنوان IP للطابعة',
                hintText: '192.168.1.100',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'المنفذ',
                hintText: '9100',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _busy ? null : _saveNetwork,
              child: const Text('حفظ إعدادات الشبكة'),
            ),
          ],
          if (_engine == PrinterEngineType.kushkNative) ...[
            const SizedBox(height: 16),
            const Text(
              'الطابعات المكتشفة',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (_busy && _devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_devices.isEmpty)
              const Text(
                'لا توجد طابعة ظاهرة حالياً. اضغط «إعادة البحث عن الطابعة».',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else
              ..._devices.map((device) {
                final id =
                    (device['id'] ?? device['address'] ?? '').toString();
                final selected = id == _selectedDeviceId;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      (device['type']?.toString().toUpperCase() == 'USB')
                          ? Icons.usb
                          : (device['type']?.toString().toUpperCase() ==
                                  'CENTERM')
                              ? Icons.print
                              : Icons.bluetooth,
                    ),
                    title: Text('${device['name'] ?? id}'),
                    subtitle: Text('${device['type'] ?? ''} • $id'),
                    trailing: selected
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.chevron_left),
                    onTap: _busy ? null : () => _selectDevice(device),
                  ),
                );
              }),
            const SizedBox(height: 16),
            const Text(
              'سائق DNZ card الأصلي',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: drivers
                  .map(
                    (d) => ChoiceChip(
                      label: Text(d),
                      selected: _driver == d,
                      onSelected: _busy ? null : (_) => _setDriver(d),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _busy ? null : _test,
            icon: const Icon(Icons.print),
            label: const Text('طباعة اختبارية'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('تحديث'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    await PrinterAccessGuard.requestWithExplanation(context);
                  },
            icon: const Icon(Icons.security),
            label: const Text('طلب صلاحيات الطابعة'),
          ),
        ],
      ),
    );
  }
}
