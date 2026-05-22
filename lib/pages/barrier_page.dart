import 'dart:async';

import 'package:flutter/material.dart';

import '../models/barrier_event.dart';
import '../services/api_client.dart';
import '../services/barrier_service.dart';
import '../utils/error_helper.dart';
import 'qr_scanner_page.dart';

class BarrierPage extends StatelessWidget {
  const BarrierPage({super.key});

  @override
  Widget build(BuildContext context) {
    final role = ApiClient.instance.userRole ?? 'resident';
    if (role == 'admin' || role == 'guard') {
      return const _AdminBarrierPage();
    }
    return const _ResidentBarrierPage();
  }
}

// ─────────────────────────────────────────────────────────────
// RESIDENT VIEW
// ─────────────────────────────────────────────────────────────

class _ResidentBarrierPage extends StatefulWidget {
  const _ResidentBarrierPage();

  @override
  State<_ResidentBarrierPage> createState() => _ResidentBarrierPageState();
}

class _ResidentBarrierPageState extends State<_ResidentBarrierPage> {
  bool _loading = true;
  List<BarrierEvent> _events = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() { _loading = true; _error = null; });
      final events = await BarrierService.instance.getMyEvents();
      if (!mounted) return;
      setState(() { _events = events; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Шлагбаум')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            const Text('История въездов и выездов', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _events.isEmpty
                          ? const Center(child: Text('Нет событий'))
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.builder(
                                itemCount: _events.length,
                                itemBuilder: (_, i) => _EventTile(event: _events[i]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ADMIN VIEW
// ─────────────────────────────────────────────────────────────

class _AdminBarrierPage extends StatelessWidget {
  const _AdminBarrierPage();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Шлагбаум'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'История'),
              Tab(text: 'Неизвестные ТС'),
              Tab(text: 'Управление'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _HistoryTab(),
            _UnknownTab(),
            _ControlTab(),
          ],
        ),
      ),
    );
  }
}

// ──── Вкладка "История" ────

class _HistoryTab extends StatefulWidget {
  const _HistoryTab();

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  bool _loading = true;
  List<BarrierEvent> _events = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() { _loading = true; _error = null; });
      final events = await BarrierService.instance.getAllEvents();
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
    if (_events.isEmpty) return const Center(child: Text('История пуста'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _events.length,
        itemBuilder: (_, i) => _EventTile(event: _events[i], showOwner: true),
      ),
    );
  }
}

// ──── Вкладка "Неизвестные ТС" ────

class _UnknownTab extends StatefulWidget {
  const _UnknownTab();

  @override
  State<_UnknownTab> createState() => _UnknownTabState();
}

class _UnknownTabState extends State<_UnknownTab> {
  bool _loading = true;
  List<BarrierEvent> _events = [];
  String? _error;
  final Set<String> _processing = {};
  StreamSubscription<List<BarrierEvent>>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    // Авто-обновление при FCM unknown_vehicle — без ручного pull-to-refresh
    _sub = BarrierService.instance.unknownEventsStream.listen((events) {
      if (!mounted) return;
      setState(() { _events = events; _loading = false; });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      setState(() { _loading = true; _error = null; });
      final events = await BarrierService.instance.getUnknownVehicles();
      if (!mounted) return;
      setState(() { _events = events; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _approve(String eventId) async {
    setState(() => _processing.add(eventId));
    try {
      await BarrierService.instance.approveUnknown(eventId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _processing.remove(eventId));
    }
  }

  Future<void> _reject(String eventId) async {
    setState(() => _processing.add(eventId));
    try {
      await BarrierService.instance.rejectUnknown(eventId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _processing.remove(eventId));
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_events.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: 120),
            Center(child: Text('Нет ожидающих решения автомобилей')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _events.length,
        itemBuilder: (_, i) {
          final e = _events[i];
          final busy = _processing.contains(e.id);
          return Card(
            color: Colors.red.withOpacity(0.08),
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.red),
                      const SizedBox(width: 8),
                      Text(
                        e.plateNumber ?? 'Неизвестный',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                      const Spacer(),
                      Text(
                        e.direction?.label ?? '',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_fmtDate(e.createdAt), style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy ? null : () => _approve(e.id),
                          style: FilledButton.styleFrom(backgroundColor: Colors.green),
                          icon: const Icon(Icons.check),
                          label: const Text('Открыть'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : () => _reject(e.id),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                          icon: const Icon(Icons.close),
                          label: const Text('Отклонить'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ──── Вкладка "Управление" ────

class _ControlTab extends StatefulWidget {
  const _ControlTab();

  @override
  State<_ControlTab> createState() => _ControlTabState();
}

class _ControlTabState extends State<_ControlTab> {
  String _direction = 'IN';
  bool _opening = false;

  Future<void> _openManual() async {
    setState(() => _opening = true);
    try {
      await BarrierService.instance.openManual(direction: _direction);
      if (!mounted) return;
      _snack('Шлагбаум открыт (${_direction == 'IN' ? 'въезд' : 'выезд'})');
    } catch (e) {
      if (!mounted) return;
      _snack('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Ручное открытие ──
        Text('Ручное открытие', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'IN', label: Text('Въезд'), icon: Icon(Icons.arrow_downward)),
            ButtonSegment(value: 'OUT', label: Text('Выезд'), icon: Icon(Icons.arrow_upward)),
          ],
          selected: {_direction},
          onSelectionChanged: (s) => setState(() => _direction = s.first),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: _opening ? null : _openManual,
            icon: const Icon(Icons.garage),
            label: Text(_opening ? 'Открываем...' : 'Открыть шлагбаум'),
          ),
        ),
        const SizedBox(height: 28),

        // ── Сканировать QR ──
        Text('Сканировать QR пропуск', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QRScannerPage()),
            ),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Открыть сканер QR'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────

class _EventTile extends StatelessWidget {
  final BarrierEvent event;
  final bool showOwner;

  const _EventTile({required this.event, this.showOwner = false});

  @override
  Widget build(BuildContext context) {
    final dirIcon = event.direction == BarrierDirection.inn
        ? Icons.arrow_circle_down
        : event.direction == BarrierDirection.out
            ? Icons.arrow_circle_up
            : Icons.help_outline;

    final typeColor = switch (event.eventType) {
      BarrierEventType.autoRecognized => Colors.green,
      BarrierEventType.qrScan => Colors.blue,
      BarrierEventType.manual => Colors.orange,
      BarrierEventType.unknown => Colors.red,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(dirIcon, color: typeColor, size: 30),
        title: Text(
          event.plateNumber ?? event.eventType.typeLabel,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.eventType.typeLabel, style: TextStyle(color: typeColor, fontSize: 12)),
            if (showOwner && event.ownerName != null)
              Text(event.ownerName!, style: const TextStyle(fontSize: 12)),
            Text(_fmtDate(event.createdAt), style: const TextStyle(fontSize: 11)),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}

String _fmtDate(DateTime dt) {
  final l = dt.toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(l.day)}.${p(l.month)}.${l.year} ${p(l.hour)}:${p(l.minute)}';
}
