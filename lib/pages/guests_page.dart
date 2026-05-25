import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/parking_spot.dart';
import '../services/api_client.dart';
import '../services/parking_service.dart';
import '../utils/error_helper.dart';

class GuestsPage extends StatefulWidget {
  const GuestsPage({super.key});

  @override
  State<GuestsPage> createState() => _GuestsPageState();
}

class _GuestsPageState extends State<GuestsPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _car = TextEditingController();
  final ApiClient _api = ApiClient.instance;

  DateTime? _from;
  DateTime? _to;
  bool _byCar = true;
  bool _loading = false;
  bool _loadingPasses = true;
  String? _error;
  List<_GuestPass> _passes = [];
  List<ParkingSpot> _guestSpots = [];
  String? _selectedGuestSpotId;

  @override
  void initState() {
    super.initState();
    _loadPasses();
    _loadGuestSpots();
  }

  Future<void> _loadGuestSpots() async {
    try {
      final spots = await ParkingService.instance.getSpots();
      if (!mounted) return;
      setState(() {
        _guestSpots = spots
            .where((s) => s.type == ParkingSpotType.guest)
            .toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _car.dispose();
    super.dispose();
  }

  Future<void> _loadPasses() async {
    try {
      setState(() { _loadingPasses = true; _error = null; });
      if (!_api.isLoggedIn) {
        setState(() { _passes = []; _loadingPasses = false; });
        return;
      }
      final res = await _api.get('/guest-access');
      final items = (res.data as List)
          .map((row) => _GuestPass.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
      if (!mounted) return;
      setState(() { _passes = items; _loadingPasses = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loadingPasses = false; });
    }
  }

  Future<void> _pickDateTime({required bool isFrom}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      initialDate: isFrom ? (_from ?? now) : (_to ?? _from ?? now),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(isFrom ? (_from ?? now) : (_to ?? _from ?? now)),
    );
    if (time == null) return;

    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isFrom) {
        _from = dt;
        if (_to != null && !_to!.isAfter(_from!)) _to = null;
      } else {
        _to = dt;
      }
    });
  }

  String _fmt(DateTime dt) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(dt.day)}.${p(dt.month)}.${dt.year} ${p(dt.hour)}:${p(dt.minute)}';
  }

  String _statusLabel(String status) => switch (status) {
    'active'   => 'Активен',
    'arrived'  => 'На территории',
    'used'     => 'Использован',
    'expired'  => 'Истёк',
    'cancelled' => 'Отменён',
    _ => status,
  };

  Future<void> _createPass() async {
    final name = _name.text.trim();
    if (name.isEmpty) { _snack('Введите имя гостя'); return; }
    if (_from == null || _to == null) { _snack('Выберите время "с" и "по"'); return; }
    if (!_to!.isAfter(_from!)) { _snack('Время "по" должно быть позже времени "с"'); return; }
    if (_byCar && _car.text.trim().isEmpty) { _snack('Введите номер авто или выключите режим "Гость на авто"'); return; }

    setState(() => _loading = true);

    try {
      final res = await _api.post('/guest-access', data: {
        'guest_name': name,
        'guest_phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'car_number': _byCar ? _car.text.trim() : null,
        'access_type': _byCar ? 'car' : 'walk',
        'valid_from': _from!.toUtc().toIso8601String(),
        'valid_until': _to!.toUtc().toIso8601String(),
        if (_byCar && _selectedGuestSpotId != null)
          'parking_spot_id': _selectedGuestSpotId,
      });

      final code = res.data['access_code'] as String;
      final qr = res.data['qr_code']?.toString();
      _name.clear(); _phone.clear(); _car.clear();
      setState(() { _from = null; _to = null; _byCar = true; _selectedGuestSpotId = null; });
      await Future.wait([_loadPasses(), _loadGuestSpots()]);

      if (!mounted) return;
      setState(() => _loading = false);
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Пропуск создан'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('Код: $code\n\nГость: $name'),
                  if (qr != null) ...[
                    const SizedBox(height: 16),
                    QrImageView(data: qr, size: 160),
                    const SizedBox(height: 6),
                    const Text('Покажите этот QR охраннику', textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ок'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancelPass(_GuestPass pass) async {
    try {
      await _api.put('/guest-access/${pass.id}/cancel');
      await _loadPasses();
      if (!mounted) return;
      _snack('Пропуск отменён');
    } catch (e) {
      if (!mounted) return;
      _snack('Ошибка отмены пропуска: $e');
    }
  }

  Set<String> get _myActivePassSpotIds => _passes
      .where((p) => (p.status == 'active' || p.status == 'arrived') && p.parkingSpotId != null)
      .map((p) => p.parkingSpotId!)
      .toSet();

  Future<void> _reportGuestSpotToAdmin(ParkingSpot spot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Гостевое место занято'),
        content: Text(
          'Место ${spot.spotNumber} занято, хотя для него есть активный пропуск. Сообщить администратору?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Сообщить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.post('/service-requests', data: {
        'category': 'Паркинг',
        'description': 'Гостевое место ${spot.spotNumber} занято посторонним ТС, хотя для него есть активный гостевой пропуск.',
      });
      if (!mounted) return;
      _snack('Заявка администратору отправлена');
    } catch (e) {
      if (!mounted) return;
      _snack(friendlyError(e));
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Гости в ЖК')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadPasses,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Оформить пропуск', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      TextField(controller: _name, enabled: !_loading, decoration: const InputDecoration(labelText: 'Имя гостя', border: OutlineInputBorder())),
                      const SizedBox(height: 12),
                      TextField(controller: _phone, enabled: !_loading, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Телефон (опционально)', border: OutlineInputBorder())),
                      const SizedBox(height: 12),
                      SwitchListTile(value: _byCar, onChanged: _loading ? null : (v) => setState(() => _byCar = v), title: const Text('Гость на авто')),
                      if (_byCar) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _car,
                          enabled: !_loading,
                          decoration: const InputDecoration(
                            labelText: 'Номер авто',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Гостевое место (необязательно)',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        if (_guestSpots.isEmpty)
                          const Text('Нет гостевых мест',
                              style: TextStyle(fontSize: 12, color: Colors.black54))
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _guestSpots.map((spot) {
                              final isFree = spot.status == ParkingSpotStatus.free;
                              final isReserved = spot.status == ParkingSpotStatus.reserved;
                              final isSelected = _selectedGuestSpotId == spot.id;
                              final color = isSelected
                                  ? Colors.blue
                                  : isFree
                                      ? Colors.green
                                      : isReserved
                                          ? Colors.blue
                                          : Colors.red;
                              final label = isFree
                                  ? 'Своб.'
                                  : isReserved
                                      ? 'Бронь'
                                      : 'Занято';
                              final isMyOccupied = !isFree &&
                                  !isReserved &&
                                  _myActivePassSpotIds.contains(spot.id);
                              return GestureDetector(
                                onTap: _loading
                                    ? null
                                    : isMyOccupied
                                        ? () => _reportGuestSpotToAdmin(spot)
                                        : !isFree
                                            ? () => _snack(
                                                isReserved
                                                    ? 'Место ${spot.spotNumber} забронировано. Выберите другое место.'
                                                    : 'Место ${spot.spotNumber} занято. Выберите другое место.')
                                            : () => setState(() =>
                                                _selectedGuestSpotId =
                                                    isSelected ? null : spot.id),
                                child: Container(
                                  width: 64,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: isSelected ? 0.2 : 0.1),
                                    border: Border.all(
                                        color: color.withValues(alpha: isSelected ? 1.0 : 0.5),
                                        width: isSelected ? 2 : 1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.local_parking,
                                          color: color, size: 16),
                                      const SizedBox(height: 2),
                                      Text(spot.spotNumber,
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: color),
                                          textAlign: TextAlign.center),
                                      Text(label,
                                          style: TextStyle(fontSize: 9, color: color)),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        if (_selectedGuestSpotId != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Выбрано: ${_guestSpots.firstWhere((s) => s.id == _selectedGuestSpotId).spotNumber}',
                            style: const TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : () => _pickDateTime(isFrom: true),
                          icon: const Icon(Icons.schedule),
                          label: Text(_from == null ? 'С: выбрать' : 'С: ${_fmt(_from!)}'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _loading || _from == null ? null : () => _pickDateTime(isFrom: false),
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(_to == null ? 'По: выбрать' : 'По: ${_fmt(_to!)}'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _loading ? null : _createPass,
                          child: _loading
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Создать пропуск'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Активные и прошлые пропуска', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              if (_loadingPasses)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _loadPasses, child: const Text('Повторить')),
                    ]),
                  ),
                )
              else if (_passes.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Пропусков пока нет')))
              else
                ..._passes.map((pass) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(pass.accessType == 'car' ? Icons.directions_car : Icons.directions_walk),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(pass.guestName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                            ),
                            if (pass.status == 'active')
                              PopupMenuButton<String>(
                                onSelected: (v) { if (v == 'cancel') _cancelPass(pass); },
                                itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('Отменить'))],
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Код: ${pass.accessCode}  ·  ${_statusLabel(pass.status)}'
                          '\nС: ${_fmt(pass.validFrom)}\nПо: ${_fmt(pass.validUntil)}'
                          '${pass.carNumber != null && pass.carNumber!.isNotEmpty ? "\nАвто: ${pass.carNumber}" : ""}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        if (pass.qrCode != null && pass.qrCode!.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Center(
                            child: Column(
                              children: [
                                QrImageView(data: pass.qrCode!, size: 180),
                                const SizedBox(height: 6),
                                const Text(
                                  'Покажите этот QR охраннику',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuestPass {
  final String id;
  final String guestName;
  final String? guestPhone;
  final String? carNumber;
  final String accessType;
  final String accessCode;
  final String? qrCode;
  final DateTime validFrom;
  final DateTime validUntil;
  final String status;
  final String? parkingSpotId;

  const _GuestPass({
    required this.id,
    required this.guestName,
    required this.guestPhone,
    required this.carNumber,
    required this.accessType,
    required this.accessCode,
    required this.qrCode,
    required this.validFrom,
    required this.validUntil,
    required this.status,
    required this.parkingSpotId,
  });

  factory _GuestPass.fromMap(Map<String, dynamic> map) => _GuestPass(
    id: (map['id'] ?? '').toString(),
    guestName: (map['guest_name'] ?? '').toString(),
    guestPhone: map['guest_phone']?.toString(),
    carNumber: map['car_number']?.toString(),
    accessType: (map['access_type'] ?? 'walk').toString(),
    accessCode: (map['access_code'] ?? '').toString(),
    qrCode: map['qr_code']?.toString(),
    validFrom: DateTime.tryParse((map['valid_from'] ?? '').toString()) ?? DateTime.now(),
    validUntil: DateTime.tryParse((map['valid_until'] ?? '').toString()) ?? DateTime.now(),
    status: (map['status'] ?? 'active').toString(),
    parkingSpotId: map['parking_spot_id']?.toString(),
  );
}
