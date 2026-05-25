import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../models/parking_booking.dart';
import '../models/parking_event.dart';
import '../models/parking_permit.dart';
import '../models/parking_spot.dart';
import '../services/api_client.dart';
import '../services/parking_service.dart';
import '../utils/error_helper.dart';
import 'service_requests_page.dart';

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
  List<ParkingPermit> _permits = [];
  bool _appealRejected = false;

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
        _service.getMyPermits(),
        ApiClient.instance.get('/service-requests'),
      ]);
      if (!mounted) return;
      final serviceRequests = ((results[2] as dynamic).data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _spots = results[0] as List<ParkingSpot>;
        _permits = results[1] as List<ParkingPermit>;
        _appealRejected = serviceRequests.any(
          (r) => ((r['description'] as String?) ?? '').contains('Апелляция по паркингу') &&
                  r['status'] == 'rejected',
        );
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
                        appealRejected: _appealRejected,
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

                      const SizedBox(height: 8),
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
// PERMIT SECTION (resident)
// ─────────────────────────────────────────────────────────────

class _PermitSection extends StatelessWidget {
  final List<ParkingPermit> permits;
  final VoidCallback onRefresh;
  final bool appealRejected;

  const _PermitSection({
    required this.permits,
    required this.onRefresh,
    this.appealRejected = false,
  });

  int get _rejectedCount => permits.where((p) => p.isRejected).length;

  @override
  Widget build(BuildContext context) {
    final activePermit = permits.isEmpty ? null : permits.first;
    final rejected = _rejectedCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Парковочный пропуск',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        if (activePermit == null)
          _NoPermitCard(
            onRefresh: onRefresh,
            rejectedCount: rejected,
            appealRejected: appealRejected,
          )
        else
          _PermitCard(
            permit: activePermit,
            onRefresh: onRefresh,
            rejectedCount: rejected,
            appealRejected: appealRejected,
          ),
      ],
    );
  }
}

class _NoPermitCard extends StatelessWidget {
  final VoidCallback onRefresh;
  final int rejectedCount;
  final bool appealRejected;
  const _NoPermitCard({
    required this.onRefresh,
    this.rejectedCount = 0,
    this.appealRejected = false,
  });

  @override
  Widget build(BuildContext context) {
    final blocked = rejectedCount >= 3;
    final deadEnd = blocked && appealRejected;

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
            if (rejectedCount > 0 && !deadEnd) ...[
              const SizedBox(height: 6),
              Text(
                'Отклонено заявок: $rejectedCount / 3',
                style: TextStyle(
                  fontSize: 12,
                  color: blocked ? Colors.red : Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (deadEnd)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Апелляция отклонена. Для решения вопроса обратитесь лично в управляющую компанию.',
                        style: TextStyle(fontSize: 13, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: blocked
                    ? FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                        onPressed: () => _openSupportRequest(context),
                        icon: const Icon(Icons.support_agent_outlined),
                        label: const Text('Обратиться в поддержку'),
                      )
                    : FilledButton.icon(
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

  void _openSupportRequest(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ServiceRequestsPage(
          prefilledTitle: 'Апелляция по паркингу',
        ),
      ),
    );
  }
}

class _PermitCard extends StatefulWidget {
  final ParkingPermit permit;
  final VoidCallback onRefresh;
  final int rejectedCount;
  final bool appealRejected;
  const _PermitCard({
    required this.permit,
    required this.onRefresh,
    this.rejectedCount = 0,
    this.appealRejected = false,
  });

  @override
  State<_PermitCard> createState() => _PermitCardState();
}

class _PermitCardState extends State<_PermitCard> {
  bool _uploading = false;
  bool _openingDoc = false;

  Future<void> _openDoc() async {
    final rawUrl = widget.permit.documentUrl;
    if (rawUrl == null) return;
    final host = ApiClient.baseHost;
    final url = rawUrl
        .replaceFirst(RegExp(r'http://localhost:\d+'), host)
        .replaceFirst(RegExp(r'http://127\.0\.0\.1:\d+'), host)
        .replaceFirst(RegExp(r'http://10\.0\.2\.2:\d+'), host);
    final fileName = url.split('/').last.isNotEmpty ? url.split('/').last : 'document';

    setState(() => _openingDoc = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Загрузка…'), duration: Duration(seconds: 60)),
    );
    try {
      final res = await ApiClient.instance.downloadBytes(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (res.statusCode != 200 || res.data == null || res.data!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить файл (HTTP ${res.statusCode})')),
        );
        return;
      }
      final bytes = Uint8List.fromList(res.data!);
      final contentType = res.headers.value('content-type') ?? '';
      final n = fileName.toLowerCase();
      final isImage = n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png') ||
          n.endsWith('.webp') || contentType.startsWith('image/');
      final isPdf = n.endsWith('.pdf') || contentType.contains('pdf');
      if (isImage) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis)),
            body: InteractiveViewer(
              minScale: 0.5, maxScale: 5,
              child: Center(child: Image.memory(bytes)),
            ),
          ),
        ));
      } else if (isPdf) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => _DocViewerPage(title: fileName, bytes: bytes),
        ));
      } else {
        final dir = await getTemporaryDirectory();
        final clean = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final file = File('${dir.path}/$clean');
        await file.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        final result = await OpenFile.open(file.path);
        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Нет приложения для этого формата: ${result.message}')),
          );
        }
      }
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сети: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _openingDoc = false);
    }
  }

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
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openingDoc ? null : _openDoc,
                  icon: _openingDoc
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.insert_drive_file_outlined, size: 16),
                  label: const Text('Открыть документ'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
            if (p.isRejected) ...[
              const SizedBox(height: 12),
              if (!widget.appealRejected || widget.rejectedCount < 3)
                Text(
                  'Отклонено заявок: ${widget.rejectedCount} / 3',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.rejectedCount >= 3 ? Colors.red : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              const SizedBox(height: 8),
              if (widget.appealRejected && widget.rejectedCount >= 3)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Апелляция отклонена. Для решения вопроса обратитесь лично в управляющую компанию.',
                          style: TextStyle(fontSize: 13, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: widget.rejectedCount >= 3
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ServiceRequestsPage(
                                prefilledTitle: 'Апелляция по паркингу',
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.support_agent_outlined),
                          label: const Text('Обратиться в поддержку'),
                        )
                      : FilledButton.icon(
                          onPressed: () async {
                            await showDialog(
                              context: context,
                              builder: (_) => _PermitSubmitDialog(onSubmitted: widget.onRefresh),
                            );
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Подать снова'),
                        ),
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
  List<ParkingSpot> _permanentSpots = [];
  String? _selectedVehicleId;
  String? _selectedSpotId;
  File? _docFile;
  String? _docFileName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/vehicles'),
        ParkingService.instance.getSpots(),
      ]);
      if (!mounted) return;
      setState(() {
        _vehicles = ((results[0] as dynamic).data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _permanentSpots = (results[1] as List<ParkingSpot>)
            .where((s) => s.type == ParkingSpotType.permanent)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _pickDoc() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.single.path == null) return;
    setState(() {
      _docFile = File(result.files.single.path!);
      _docFileName = result.files.single.name;
    });
  }

  Future<void> _submit() async {
    if (_selectedVehicleId == null || _docFile == null) return;
    setState(() { _submitting = true; _error = null; });
    try {
      final permit = await ParkingService.instance.submitPermit(
        _selectedVehicleId!,
        spotId: _selectedSpotId,
      );
      await ParkingService.instance.uploadPermitDocument(permit.id, _docFile!);
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
    final canSubmit = !_submitting &&
        _selectedVehicleId != null &&
        _docFile != null &&
        _vehicles.isNotEmpty;

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
                      'Выберите автомобиль',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
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
                        return RadioListTile<String>(
                          value: id,
                          groupValue: _selectedVehicleId,
                          onChanged: (val) =>
                              setState(() => _selectedVehicleId = val),
                          title: Text(plate,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: brand.isNotEmpty ? Text(brand) : null,
                          contentPadding: EdgeInsets.zero,
                        );
                      }),
                    const SizedBox(height: 16),
                    const Text(
                      'Желаемое парковочное место (необязательно)',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (_permanentSpots.isEmpty)
                      const Text('Нет доступных постоянных мест',
                          style: TextStyle(fontSize: 12, color: Colors.black54))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _permanentSpots.map((spot) {
                          final isAssigned = spot.assignedUserId != null;
                          final isFree = spot.status == ParkingSpotStatus.free && !isAssigned;
                          final isSelected = _selectedSpotId == spot.id;
                          final color = isSelected
                              ? Colors.blue
                              : isFree
                                  ? Colors.green
                                  : Colors.red;
                          return GestureDetector(
                            onTap: isAssigned
                                ? null
                                : () => setState(() =>
                                    _selectedSpotId =
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
                                  Text(
                                    isFree ? 'Своб.' : 'Занято',
                                    style: TextStyle(
                                        fontSize: 9, color: color),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    if (_selectedSpotId != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Выбрано: ${_permanentSpots.firstWhere((s) => s.id == _selectedSpotId).spotNumber}',
                        style: const TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'Прикрепите документ (обязательно)',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _submitting ? null : _pickDoc,
                        icon: Icon(
                          _docFile != null
                              ? Icons.check_circle_outline
                              : Icons.upload_file_outlined,
                          color: _docFile != null ? Colors.green : null,
                        ),
                        label: Text(
                          _docFileName ?? 'Выбрать файл (PDF, JPG, PNG)',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _docFile != null ? Colors.green : null,
                          ),
                        ),
                      ),
                    ),
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
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: canSubmit ? _submit : null,
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

class _DocViewerPage extends StatefulWidget {
  final String title;
  final List<int> bytes;
  const _DocViewerPage({required this.title, required this.bytes});

  @override
  State<_DocViewerPage> createState() => _DocViewerPageState();
}

class _DocViewerPageState extends State<_DocViewerPage> {
  bool _ready = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Stack(
        children: [
          PDFView(
            pdfData: Uint8List.fromList(widget.bytes),
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            onRender: (_) => setState(() => _ready = true),
            onError: (e) => setState(() => _error = e.toString()),
            onPageError: (_, e) => setState(() => _error = e.toString()),
          ),
          if (!_ready && _error == null)
            const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Не удалось отобразить PDF: $_error',
                    textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }
}
