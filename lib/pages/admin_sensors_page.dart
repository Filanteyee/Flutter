import 'dart:async';

import 'package:flutter/material.dart';

import '../models/sensor.dart';
import '../services/sensor_service.dart';
import '../widgets/sensor_widgets.dart';
import 'admin_stats_page.dart';
import 'sensor_event_detail_page.dart';

class AdminSensorsPage extends StatefulWidget {
  /// Если задан — после загрузки откроется вкладка нужного подъезда и событие
  /// с этим id будет подсвечено. Используется при навигации по FCM-пушу.
  final String? highlightEventId;

  const AdminSensorsPage({super.key, this.highlightEventId});

  @override
  State<AdminSensorsPage> createState() => _AdminSensorsPageState();
}

class _AdminSensorsPageState extends State<AdminSensorsPage>
    with SingleTickerProviderStateMixin {
  final SensorService _service = SensorService.instance;

  late TabController _tabs;
  bool _loading = true;
  String? _error;

  List<Sensor> _sensors = [];
  List<SensorEvent> _events = [];
  StreamSubscription<List<SensorEvent>>? _eventsSub;
  StreamSubscription<List<Sensor>>? _sensorsSub;
  bool _highlightConsumed = false;
  bool _gridView = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: kEntrancesCount, vsync: this);
    _load();
    _eventsSub = _service.eventsStream.listen((events) {
      if (!mounted) return;
      final sorted = [...events]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() => _events = sorted);
    });
    _sensorsSub = _service.sensorsStream.listen((sensors) {
      if (!mounted) return;
      setState(() => _sensors = sensors);
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _sensorsSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sensors = await _service.getAllSensors();
      final events = await _service.getEvents();
      if (!mounted) return;
      setState(() {
        _sensors = sensors;
        _events = events;
        _loading = false;
      });
      _applyHighlight();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка загрузки: $e';
        _loading = false;
      });
    }
  }

  int get _totalSensors => _sensors.length;
  int get _normalCount =>
      _sensors.where((s) => s.status == SensorStatus.normal).length;
  int get _alertCount =>
      _sensors.where((s) => s.status == SensorStatus.alert).length;
  int get _offlineCount =>
      _sensors.where((s) => s.status == SensorStatus.offline).length;

  void _applyHighlight() {
    final id = widget.highlightEventId;
    if (id == null || _highlightConsumed) return;
    SensorEvent? event;
    for (final e in _events) {
      if (e.id == id) {
        event = e;
        break;
      }
    }
    if (event == null) return;
    _highlightConsumed = true;
    final tabIndex = event.entranceNum - 1;
    if (tabIndex >= 0 && tabIndex < _tabs.length) {
      _tabs.animateTo(tabIndex);
    }
  }

  SensorEvent? _activeEventForSensor(String sensorId) {
    for (final e in _events) {
      if (e.sensorId != sensorId) continue;
      if (e.status == EventStatus.falseAlarm) continue;
      return e;
    }
    return null;
  }

  bool _isMissing(Sensor s) => s.id.startsWith('missing-');

  Future<void> _openSensor(Sensor sensor) async {
    if (_isMissing(sensor)) return;
    final event = _activeEventForSensor(sensor.id);
    if (event == null) {
      final lastSeen = sensor.lastSeenAt ?? sensor.lastUpdated;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${sensor.type.shortLabel}: ${sensor.status.label}, '
            'виден ${formatSensorTime(lastSeen)}',
          ),
        ),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SensorEventDetailPage(eventId: event.id),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Датчики · администратор'),
        actions: [
          if (!_loading && _error == null) ...[
            IconButton(
              icon: const Icon(Icons.bar_chart),
              tooltip: 'Статистика',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminStatsPage(),
                ),
              ),
            ),
            IconButton(
              icon: Icon(_gridView ? Icons.view_list : Icons.grid_view),
              tooltip: _gridView ? 'Список' : 'Сетка',
              onPressed: () => setState(() => _gridView = !_gridView),
            ),
          ],
        ],
        bottom: _gridView
            ? null
            : TabBar(
                controller: _tabs,
                isScrollable: true,
                tabs: [
                  for (int e = 1; e <= kEntrancesCount; e++)
                    Tab(text: 'Подъезд $e'),
                ],
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Column(
                    children: [
                      _StatsBar(
                        total: _totalSensors,
                        normal: _normalCount,
                        alert: _alertCount,
                        offline: _offlineCount,
                      ),
                      Expanded(
                        child: _gridView
                            ? _AdminSensorGrid(
                                sensors: _sensors,
                                events: _events,
                                onSensorTap: _openSensor,
                              )
                            : TabBarView(
                                controller: _tabs,
                                children: [
                                  for (int e = 1; e <= kEntrancesCount; e++)
                                    _EntranceTab(
                                      entrance: e,
                                      sensors: _sensors
                                          .where((s) => s.entranceNum == e)
                                          .toList(),
                                      events: _events,
                                      onSensorTap: _openSensor,
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final int total;
  final int normal;
  final int alert;
  final int offline;

  const _StatsBar({
    required this.total,
    required this.normal,
    required this.alert,
    required this.offline,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'Всего',
              value: '$total',
              color: Theme.of(context).colorScheme.primary,
              icon: Icons.sensors,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              label: 'В норме',
              value: '$normal',
              color: Colors.green,
              icon: Icons.check_circle_outline,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              label: 'Тревоги',
              value: '$alert',
              color: Colors.red,
              icon: Icons.warning_amber_rounded,
              pulsing: alert > 0,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              label: 'Офлайн',
              value: '$offline',
              color: Colors.grey,
              icon: Icons.cloud_off_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool pulsing;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.pulsing = false,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );

    return PulsingAlert(active: pulsing, child: card);
  }
}

class _EntranceTab extends StatelessWidget {
  final int entrance;
  final List<Sensor> sensors;
  final List<SensorEvent> events;
  final ValueChanged<Sensor> onSensorTap;

  const _EntranceTab({
    required this.entrance,
    required this.sensors,
    required this.events,
    required this.onSensorTap,
  });

  SensorEvent? _activeEventFor(String sensorId) {
    for (final e in events) {
      if (e.sensorId == sensorId && e.status != EventStatus.falseAlarm) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final maxFloor = sensors.fold<int>(0, (m, s) => s.floor > m ? s.floor : m);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: maxFloor,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final floor = maxFloor - i;
        final water = sensors.firstWhere(
          (s) => s.floor == floor && s.type == SensorType.water,
          orElse: () => _missingSensor(entrance, floor, SensorType.water),
        );
        final smoke = sensors.firstWhere(
          (s) => s.floor == floor && s.type == SensorType.smoke,
          orElse: () => _missingSensor(entrance, floor, SensorType.smoke),
        );

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Этаж $floor',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _AdminSensorTile(
                        sensor: water,
                        activeEvent: _activeEventFor(water.id),
                        onTap: () => onSensorTap(water),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AdminSensorTile(
                        sensor: smoke,
                        activeEvent: _activeEventFor(smoke.id),
                        onTap: () => onSensorTap(smoke),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Sensor _missingSensor(int entrance, int floor, SensorType type) {
    return Sensor(
      id: 'missing-$entrance-$floor-${type.apiValue}',
      type: type,
      entranceNum: entrance,
      floor: floor,
      status: SensorStatus.offline,
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class _AdminSensorTile extends StatelessWidget {
  final Sensor sensor;
  final VoidCallback onTap;
  final SensorEvent? activeEvent;

  const _AdminSensorTile({
    required this.sensor,
    required this.onTap,
    this.activeEvent,
  });

  @override
  Widget build(BuildContext context) {
    final color = effectiveSensorColor(sensor, activeEvent);
    final isAlert = effectiveIsAlert(activeEvent);
    final isMissing = sensor.id.startsWith('missing-');

    final tile = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child:
                      Icon(sensorTypeIcon(sensor.type), color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sensor.type.shortLabel,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        effectiveStatusLabel(sensor, activeEvent),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isAlert && !isMissing) ...[
              const SizedBox(height: 6),
              Text(
                'Нажмите для подробностей',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: color,
                      fontSize: 11,
                    ),
              ),
            ],
          ],
        ),
      ),
    );

    return PulsingAlert(active: isAlert, child: tile);
  }
}

/// Компактная сетка всех 54 датчиков: 3 подъезда × 9 этажей × 2 иконки.
class _AdminSensorGrid extends StatelessWidget {
  final List<Sensor> sensors;
  final List<SensorEvent> events;
  final ValueChanged<Sensor> onSensorTap;

  const _AdminSensorGrid({
    required this.sensors,
    required this.events,
    required this.onSensorTap,
  });

  Sensor _missing(int entrance, int floor, SensorType type) => Sensor(
        id: 'missing-$entrance-$floor-${type.apiValue}',
        type: type,
        entranceNum: entrance,
        floor: floor,
        status: SensorStatus.offline,
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
      );

  Sensor _find(int entrance, int floor, SensorType type) =>
      sensors.firstWhere(
        (s) =>
            s.entranceNum == entrance &&
            s.floor == floor &&
            s.type == type,
        orElse: () => _missing(entrance, floor, type),
      );

  SensorEvent? _activeEventFor(String sensorId) {
    for (final e in events) {
      if (e.sensorId == sensorId && e.status != EventStatus.falseAlarm) return e;
    }
    return null;
  }

  Widget _cell(int entrance, int floor) {
    final water = _find(entrance, floor, SensorType.water);
    final smoke = _find(entrance, floor, SensorType.smoke);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GridIcon(
              sensor: water,
              activeEvent: _activeEventFor(water.id),
              onTap: () => onSensorTap(water),
            ),
            const SizedBox(width: 4),
            _GridIcon(
              sensor: smoke,
              activeEvent: _activeEventFor(smoke.id),
              onTap: () => onSensorTap(smoke),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        );

    final rows = <TableRow>[
      // Заголовок: П1 / П2 / П3
      TableRow(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
        children: [
          const SizedBox(height: 32),
          for (int e = 1; e <= kEntrancesCount; e++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Center(child: Text('П$e', style: labelStyle)),
            ),
        ],
      ),
      // Этажи сверху вниз: 9 → 1
      for (int floor = kFloorsPerEntrance; floor >= 1; floor--)
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Center(child: Text('$floor', style: labelStyle)),
            ),
            for (int e = 1; e <= kEntrancesCount; e++) _cell(e, floor),
          ],
        ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FixedColumnWidth(30),
          1: FlexColumnWidth(),
          2: FlexColumnWidth(),
          3: FlexColumnWidth(),
        },
        children: rows,
      ),
    );
  }
}

/// Круглая иконка датчика в сетке. NORMAL=зелёная, ALERT=красная+пульс,
/// OFFLINE=серая.
class _GridIcon extends StatelessWidget {
  final Sensor sensor;
  final SensorEvent? activeEvent;
  final VoidCallback onTap;

  const _GridIcon({
    required this.sensor,
    required this.onTap,
    this.activeEvent,
  });

  @override
  Widget build(BuildContext context) {
    final color = effectiveSensorColor(sensor, activeEvent);
    final isAlert = effectiveIsAlert(activeEvent);

    final icon = InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(sensorTypeIcon(sensor.type), color: color, size: 18),
      ),
    );

    return PulsingAlert(active: isAlert, child: icon);
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
