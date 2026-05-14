import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/parking_booking.dart';
import '../models/parking_event.dart';
import '../models/parking_permit.dart';
import '../models/parking_spot.dart';
import '../services/api_client.dart';
import '../services/parking_service.dart';
import '../utils/error_helper.dart';

class ParkingPage extends StatelessWidget {
  const ParkingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final role = ApiClient.instance.userRole ?? 'resident';
    if (role == 'admin') return const _AdminParkingPage();
    return const _ResidentParkingPage();
  }
}

// ─────────────────────────────────────────────────────────────
// RESIDENT VIEW
// ─────────────────────────────────────────────────────────────

class _ResidentParkingPage extends StatefulWidget {
  const _ResidentParkingPage();

  @override
  State<_ResidentParkingPage> createState() => _ResidentParkingPageState();
}

class _ResidentParkingPageState extends State<_ResidentParkingPage> {
  final _service = ParkingService.instance;

  bool _loading = true;
  String? _error;
  List<ParkingSpot> _spots = [];
  List<ParkingBooking> _bookings = [];
  List<ParkingPermit> _permits = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() { _loading = true; _error = null; });
      final results = await Future.wait([
        _service.getSpots(),
        _service.getMyBookings(),
        _service.getMyPermits(),
      ]);
      if (!mounted) return;
      setState(() {
        _spots = results[0] as List<ParkingSpot>;
        _bookings = results[1] as List<ParkingBooking>;
        _permits = results[2] as List<ParkingPermit>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  ParkingSpot? get _myPermanentSpot {
    final userId = ApiClient.instance.userId;
    if (userId == null) return null;
    try {
      return _spots.firstWhere(
        (s) => s.type == ParkingSpotType.permanent && s.assignedUserId == userId,
      );
    } catch (_) {
      return null;
    }
  }

  List<ParkingSpot> get _guestSpots =>
      _spots.where((s) => s.type == ParkingSpotType.guest).toList();

  Set<String> get _myActiveSpotIds => _bookings
      .where((b) => b.status == BookingStatus.active)
      .map((b) => b.spotId)
      .toSet();

  Future<void> _showBookingSheet(ParkingSpot spot) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BookingSheet(spot: spot, onBooked: _load),
    );
  }

  Future<void> _cancelBooking(ParkingBooking booking) async {
    try {
      await _service.cancelBooking(booking.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(friendlyError(e));
    }
  }

  Future<void> _reportToAdmin(ParkingSpot spot) async {
    try {
      await ApiClient.instance.post('/service-requests', data: {
        'category': 'Паркинг',
        'description': 'Моё постоянное место ${spot.spotNumber} занято посторонним ТС.',
      });
      if (!mounted) return;
      _snack('Заявка администратору отправлена');
    } catch (e) {
      if (!mounted) return;
      _snack(friendlyError(e));
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Паркинг')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Повторить')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // ── Парковочный пропуск ──
                      _PermitSection(
                        permits: _permits,
                        onRefresh: _load,
                      ),
                      const SizedBox(height: 20),

                      // ── Моё постоянное место ──
                      if (_myPermanentSpot != null) ...[
                        _PermanentSpotCard(
                          spot: _myPermanentSpot!,
                          onReport: () => _reportToAdmin(_myPermanentSpot!),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Гостевые места ──
                      Text('Гостевые места',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      if (_guestSpots.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Нет гостевых мест'),
                          ),
                        )
                      else
                        _GuestSpotsGrid(
                          spots: _guestSpots,
                          myActiveSpotIds: _myActiveSpotIds,
                          onTap: (spot) {
                            if (spot.status == ParkingSpotStatus.free) {
                              _showBookingSheet(spot);
                            }
                          },
                        ),

                      // ── Мои брони ──
                      const SizedBox(height: 20),
                      Text('Мои бронирования',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      if (_bookings.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Нет бронирований'),
                          ),
                        )
                      else
                        ..._bookings.map(
                          (b) => _BookingCard(
                            booking: b,
                            onCancel: b.status == BookingStatus.active
                                ? () => _cancelBooking(b)
                                : null,
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ADMIN VIEW
// ─────────────────────────────────────────────────────────────

class _AdminParkingPage extends StatelessWidget {
  const _AdminParkingPage();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Паркинг'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Места'),
              Tab(text: 'Брони'),
              Tab(text: 'Журнал'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AdminSpotsTab(),
            _AdminBookingsTab(),
            _AdminEventsTab(),
          ],
        ),
      ),
    );
  }
}

// ──── Вкладка "Все места" ────

class _AdminSpotsTab extends StatefulWidget {
  const _AdminSpotsTab();

  @override
  State<_AdminSpotsTab> createState() => _AdminSpotsTabState();
}

class _AdminSpotsTabState extends State<_AdminSpotsTab> {
  bool _loading = true;
  List<ParkingSpot> _spots = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() { _loading = true; _error = null; });
      final spots = await ParkingService.instance.getAdminSpots();
      if (!mounted) return;
      setState(() { _spots = spots; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _showAssignDialog(ParkingSpot spot) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Место ${spot.spotNumber}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'ID жильца',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Назначить'),
          ),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    try {
      await ParkingService.instance.assignPermanentSpot(
        spotId: spot.id,
        userId: ctrl.text.trim(),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _spots.length,
        itemBuilder: (_, i) {
          final spot = _spots[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: _SpotStatusDot(status: spot.status),
              title: Text(
                spot.spotNumber,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${spot.type.label} · ${spot.status.label}'
                '${spot.assignedUserName != null ? '\n${spot.assignedUserName}' : ''}',
              ),
              isThreeLine: spot.assignedUserName != null,
              trailing: spot.type == ParkingSpotType.permanent
                  ? IconButton(
                      icon: const Icon(Icons.person_add_outlined),
                      onPressed: () => _showAssignDialog(spot),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

// ──── Вкладка "Брони" ────

class _AdminBookingsTab extends StatefulWidget {
  const _AdminBookingsTab();

  @override
  State<_AdminBookingsTab> createState() => _AdminBookingsTabState();
}

class _AdminBookingsTabState extends State<_AdminBookingsTab> {
  bool _loading = true;
  List<ParkingBooking> _bookings = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() { _loading = true; _error = null; });
      final bookings = await ParkingService.instance.getAllBookings();
      if (!mounted) return;
      setState(() { _bookings = bookings; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_bookings.isEmpty) return const Center(child: Text('Нет бронирований'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _bookings.length,
        itemBuilder: (_, i) => _BookingCard(booking: _bookings[i]),
      ),
    );
  }
}

// ──── Вкладка "Журнал" ────

class _AdminEventsTab extends StatefulWidget {
  const _AdminEventsTab();

  @override
  State<_AdminEventsTab> createState() => _AdminEventsTabState();
}

class _AdminEventsTabState extends State<_AdminEventsTab> {
  bool _loading = true;
  List<ParkingEvent> _events = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() { _loading = true; _error = null; });
      final events = await ParkingService.instance.getEvents();
      if (!mounted) return;
      setState(() { _events = events; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_events.isEmpty) return const Center(child: Text('Журнал пуст'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _events.length,
        itemBuilder: (_, i) {
          final e = _events[i];
          final isOccupied = e.eventType == ParkingEventType.occupied;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                isOccupied ? Icons.directions_car : Icons.check_circle_outline,
                color: isOccupied ? Colors.red : Colors.green,
              ),
              title: Text(e.spotNumber,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(e.eventType.label),
              trailing: Text(_fmtDate(e.createdAt),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────

class _PermanentSpotCard extends StatelessWidget {
  final ParkingSpot spot;
  final VoidCallback onReport;

  const _PermanentSpotCard({required this.spot, required this.onReport});

  @override
  Widget build(BuildContext context) {
    final isAlert = spot.status == ParkingSpotStatus.occupied;
    final color = isAlert ? Colors.red : Colors.green;

    return Card(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_parking, color: color, size: 28),
                const SizedBox(width: 10),
                Text(
                  'Моё место',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              spot.spotNumber,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              spot.status.label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            if (isAlert) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.red, size: 18),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Ваше место занято посторонним ТС',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onReport,
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  icon: const Icon(Icons.report_outlined),
                  label: const Text('Сообщить администратору'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuestSpotsGrid extends StatelessWidget {
  final List<ParkingSpot> spots;
  final Set<String> myActiveSpotIds;
  final void Function(ParkingSpot) onTap;

  const _GuestSpotsGrid({
    required this.spots,
    required this.myActiveSpotIds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: spots.length,
      itemBuilder: (_, i) {
        final spot = spots[i];
        final isMine = myActiveSpotIds.contains(spot.id);

        final Color color;
        if (isMine) {
          color = Colors.blue;
        } else if (spot.status == ParkingSpotStatus.free) {
          color = Colors.green;
        } else {
          color = Colors.red;
        }

        return GestureDetector(
          onTap: () => onTap(spot),
          child: Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_parking, color: color, size: 18),
                const SizedBox(height: 2),
                Text(
                  spot.spotNumber,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BookingCard extends StatelessWidget {
  final ParkingBooking booking;
  final VoidCallback? onCancel;

  const _BookingCard({required this.booking, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final isActive = booking.status == BookingStatus.active;
    final statusColor = isActive ? Colors.green : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.local_parking, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.spotNumber,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_fmtDate(booking.startTime)} — ${_fmtDate(booking.endTime)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    booking.status.label,
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
            if (onCancel != null)
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Отменить'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpotStatusDot extends StatelessWidget {
  final ParkingSpotStatus status;

  const _SpotStatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ParkingSpotStatus.free => Colors.green,
      ParkingSpotStatus.occupied => Colors.red,
      ParkingSpotStatus.reserved => Colors.blue,
    };
    return Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BOOKING SHEET
// ─────────────────────────────────────────────────────────────

class _BookingSheet extends StatefulWidget {
  final ParkingSpot spot;
  final VoidCallback onBooked;

  const _BookingSheet({required this.spot, required this.onBooked});

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  DateTime? _from;
  DateTime? _to;
  bool _saving = false;
  String? _error;

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
      initialTime: TimeOfDay.fromDateTime(isFrom ? (_from ?? now) : (_to ?? now)),
    );
    if (time == null || !mounted) return;
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

  Future<void> _confirm() async {
    if (_from == null || _to == null) {
      setState(() => _error = 'Выберите время начала и конца');
      return;
    }
    if (!_to!.isAfter(_from!)) {
      setState(() => _error = 'Время конца должно быть позже начала');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ParkingService.instance.createBooking(
        spotId: widget.spot.id,
        startTime: _from!,
        endTime: _to!,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onBooked();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Забронировать место ${widget.spot.spotNumber}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : () => _pickDateTime(isFrom: true),
              icon: const Icon(Icons.schedule),
              label: Text(_from == null ? 'С: выбрать' : 'С: ${_fmtDate(_from!)}'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_saving || _from == null)
                  ? null
                  : () => _pickDateTime(isFrom: false),
              icon: const Icon(Icons.schedule_outlined),
              label: Text(_to == null ? 'По: выбрать' : 'По: ${_fmtDate(_to!)}'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _confirm,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Забронировать'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PERMIT SECTION (resident)
// ─────────────────────────────────────────────────────────────

class _PermitSection extends StatelessWidget {
  final List<ParkingPermit> permits;
  final VoidCallback onRefresh;

  const _PermitSection({required this.permits, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final activePermit = permits.isEmpty ? null : permits.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Парковочный пропуск',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        if (activePermit == null)
          _NoPermitCard(onRefresh: onRefresh)
        else
          _PermitCard(permit: activePermit, onRefresh: onRefresh),
      ],
    );
  }
}

class _NoPermitCard extends StatelessWidget {
  final VoidCallback onRefresh;
  const _NoPermitCard({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('У вас нет пропуска на паркинг.'),
            const SizedBox(height: 2),
            const Text(
              'Чтобы въезжать на парковку, нужно получить одобренный пропуск для вашего автомобиля.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (_) => _PermitSubmitDialog(onSubmitted: onRefresh),
                  );
                },
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Подать заявку'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermitCard extends StatefulWidget {
  final ParkingPermit permit;
  final VoidCallback onRefresh;
  const _PermitCard({required this.permit, required this.onRefresh});

  @override
  State<_PermitCard> createState() => _PermitCardState();
}

class _PermitCardState extends State<_PermitCard> {
  bool _uploading = false;

  Future<void> _uploadDoc() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.single.path == null) return;
    setState(() => _uploading = true);
    try {
      await ParkingService.instance.uploadPermitDocument(
        widget.permit.id,
        File(result.files.single.path!),
      );
      widget.onRefresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.permit;
    final color = p.isApproved
        ? Colors.green
        : p.isRejected
            ? Colors.red
            : Colors.orange;

    return Card(
      color: color.withValues(alpha: 0.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  p.isApproved
                      ? Icons.verified_outlined
                      : p.isRejected
                          ? Icons.cancel_outlined
                          : Icons.hourglass_top_outlined,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(p.statusLabel,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: color)),
                const Spacer(),
                Text(p.plateNumber,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            if (p.spotNumber != null) ...[
              const SizedBox(height: 4),
              Text('Место: ${p.spotNumber}',
                  style: const TextStyle(fontSize: 13)),
            ],
            if (p.adminComment != null && p.adminComment!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Комментарий: ${p.adminComment}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
            if (p.isPending && p.documentUrl == null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _uploading ? null : _uploadDoc,
                  icon: _uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_file_outlined),
                  label: const Text('Прикрепить документ'),
                ),
              ),
            ],
            if (p.documentUrl != null) ...[
              const SizedBox(height: 4),
              const Row(
                children: [
                  Icon(Icons.attach_file, size: 14, color: Colors.black45),
                  SizedBox(width: 4),
                  Text('Документ прикреплён',
                      style: TextStyle(fontSize: 12, color: Colors.black45)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PERMIT SUBMIT DIALOG
// ─────────────────────────────────────────────────────────────

class _PermitSubmitDialog extends StatefulWidget {
  final VoidCallback onSubmitted;
  const _PermitSubmitDialog({required this.onSubmitted});

  @override
  State<_PermitSubmitDialog> createState() => _PermitSubmitDialogState();
}

class _PermitSubmitDialogState extends State<_PermitSubmitDialog> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<Map<String, dynamic>> _vehicles = [];
  String? _selectedVehicleId;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    try {
      final res = await ApiClient.instance.get('/vehicles');
      if (!mounted) return;
      setState(() {
        _vehicles = (res.data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _submit() async {
    if (_selectedVehicleId == null) return;
    setState(() { _submitting = true; _error = null; });
    try {
      await ParkingService.instance.submitPermit(_selectedVehicleId!);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSubmitted();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Заявка на пропуск'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Выберите автомобиль для которого хотите получить пропуск на паркинг.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    if (_vehicles.isEmpty)
                      const Text(
                        'У вас нет зарегистрированных автомобилей.\nСначала добавьте автомобиль в разделе «Мои автомобили».',
                        style: TextStyle(color: Colors.red),
                      )
                    else
                      ..._vehicles.map((v) {
                        final id = v['id'] as String;
                        final plate = v['plate_number'] as String? ?? '';
                        final brand = v['brand'] as String? ?? '';
                        // ignore: deprecated_member_use
                        return RadioListTile<String>(
                          value: id,
                          // ignore: deprecated_member_use
                          groupValue: _selectedVehicleId,
                          // ignore: deprecated_member_use
                          onChanged: (val) =>
                              setState(() => _selectedVehicleId = val),
                          title: Text(plate,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: brand.isNotEmpty ? Text(brand) : null,
                          contentPadding: EdgeInsets.zero,
                        );
                      }),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ],
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: (_submitting ||
                  _selectedVehicleId == null ||
                  _vehicles.isEmpty)
              ? null
              : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Подать'),
        ),
      ],
    );
  }
}

String _fmtDate(DateTime dt) {
  final l = dt.toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(l.day)}.${p(l.month)}.${l.year} ${p(l.hour)}:${p(l.minute)}';
}
