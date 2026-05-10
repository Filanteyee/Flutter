import 'dart:async';

import 'package:flutter/material.dart';

import '../models/sensor.dart';
import '../services/auth_service.dart';
import '../services/sensor_service.dart';
import '../widgets/sensor_widgets.dart';

class SensorsPage extends StatefulWidget {
  /// Если задан — после загрузки списка событий этот элемент будет подсвечен
  /// и проскроллен в видимую область. Используется при навигации по FCM-пушу.
  final String? highlightEventId;

  const SensorsPage({super.key, this.highlightEventId});

  @override
  State<SensorsPage> createState() => _SensorsPageState();
}

class _SensorsPageState extends State<SensorsPage> {
  final SensorService _service = SensorService.instance;

  int? _entrance;
  int? _floor;

  bool _loading = true;
  String? _error;
  List<Sensor> _sensors = [];
  List<SensorEvent> _events = [];
  StreamSubscription<List<SensorEvent>>? _eventsSub;
  final Map<String, GlobalKey> _eventKeys = {};
  bool _highlightConsumed = false;

  @override
  void initState() {
    super.initState();
    _load();
    _eventsSub = _service.eventsStream.listen((events) {
      if (!mounted || _entrance == null) return;
      final filtered = events
          .where((e) =>
              e.entranceNum == _entrance &&
              e.status == EventStatus.confirmed)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() => _events = filtered);
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final address = await AuthService().getResidentAddress();
      if (address == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Сначала укажите подъезд и квартиру в подтверждении статуса.';
          _loading = false;
        });
        return;
      }
      final sensors = await _service.getSensors(entrance: address.entrance);
      final events = await _service.getEvents(
        entrance: address.entrance,
        status: EventStatus.confirmed,
      );
      if (!mounted) return;
      setState(() {
        _entrance = address.entrance;
        _floor = address.floor;
        _sensors = sensors;
        _events = events;
        _loading = false;
      });
      _scrollToHighlightedEvent();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить датчики: $e';
        _loading = false;
      });
    }
  }

  void _scrollToHighlightedEvent() {
    final id = widget.highlightEventId;
    if (id == null || _highlightConsumed) return;
    if (!_events.any((e) => e.id == id)) return;
    _highlightConsumed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _eventKeys[id]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        alignment: 0.2,
      );
    });
  }

  Sensor? _sensorFor(int floor, SensorType type) {
    for (final s in _sensors) {
      if (s.floor == floor && s.type == type) return s;
    }
    return null;
  }

  void _openFloorDetails(int floor) {
    final water = _sensorFor(floor, SensorType.water);
    final smoke = _sensorFor(floor, SensorType.smoke);
    final entrance = _entrance;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Этаж $floor · Подъезд $entrance',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (water != null)
                  FloorSensorCard(sensor: water),
                const SizedBox(height: 12),
                if (smoke != null)
                  FloorSensorCard(sensor: smoke),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Датчики')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _SectionTitle('Ваш этаж (${_floor!})'),
                        const SizedBox(height: 10),
                        _MyFloorRow(
                          water: _sensorFor(_floor!, SensorType.water),
                          smoke: _sensorFor(_floor!, SensorType.smoke),
                        ),
                        const SizedBox(height: 22),
                        _SectionTitle('Подъезд ${_entrance!} — все этажи'),
                        const SizedBox(height: 10),
                        _AllFloorsList(
                          entrance: _entrance!,
                          currentFloor: _floor!,
                          sensors: _sensors,
                          onTap: _openFloorDetails,
                        ),
                        const SizedBox(height: 22),
                        const _SectionTitle('Активные события'),
                        const SizedBox(height: 10),
                        if (_events.isEmpty)
                          const _NoEventsCard()
                        else
                          ..._events.map((e) {
                            final key = _eventKeys.putIfAbsent(
                                e.id, () => GlobalKey());
                            return Padding(
                              key: key,
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ActiveEventCard(
                                event: e,
                                highlighted:
                                    e.id == widget.highlightEventId,
                              ),
                            );
                          }),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _MyFloorRow extends StatelessWidget {
  final Sensor? water;
  final Sensor? smoke;

  const _MyFloorRow({required this.water, required this.smoke});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: water == null
                ? const _MissingSensor(label: 'Датчик воды')
                : FloorSensorCard(sensor: water!),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: smoke == null
                ? const _MissingSensor(label: 'Датчик дыма')
                : FloorSensorCard(sensor: smoke!),
          ),
        ],
      ),
    );
  }
}

class _AllFloorsList extends StatelessWidget {
  final int entrance;
  final int currentFloor;
  final List<Sensor> sensors;
  final ValueChanged<int> onTap;

  const _AllFloorsList({
    required this.entrance,
    required this.currentFloor,
    required this.sensors,
    required this.onTap,
  });

  Sensor? _sensorFor(int floor, SensorType type) {
    for (final s in sensors) {
      if (s.floor == floor && s.type == type) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final maxFloor = sensors.fold<int>(0, (m, s) => s.floor > m ? s.floor : m);
    final rows = <Widget>[];
    for (int f = maxFloor; f >= 1; f--) {
      rows.add(
        FloorSummaryRow(
          floor: f,
          water: _sensorFor(f, SensorType.water),
          smoke: _sensorFor(f, SensorType.smoke),
          highlightCurrent: f == currentFloor,
          onTap: () => onTap(f),
        ),
      );
      if (f > 1) {
        rows.add(const Divider(height: 1));
      }
    }

    return Card(
      child: Column(children: rows),
    );
  }
}

class _ActiveEventCard extends StatelessWidget {
  final SensorEvent event;
  final bool highlighted;

  const _ActiveEventCard({required this.event, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final threat = event.threatType ??
        (event.type == SensorType.water ? ThreatType.waterLeak : ThreatType.fire);
    const color = Colors.red;

    return Card(
      shape: highlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.red, width: 2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(threatIcon(threat), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        threat.label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Подъезд ${event.entranceNum} · этаж ${event.floor}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if ((event.adminComment ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(event.adminComment!),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.access_time, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Подтверждено ${formatSensorTime(event.confirmedAt ?? event.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoEventsCard extends StatelessWidget {
  const _NoEventsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Активных событий нет',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingSensor extends StatelessWidget {
  final String label;
  const _MissingSensor({required this.label});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.sensors_off_outlined, color: Colors.grey),
            const SizedBox(height: 12),
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text('Нет данных', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
