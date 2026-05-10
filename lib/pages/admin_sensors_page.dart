import 'dart:async';

import 'package:flutter/material.dart';

import '../models/sensor.dart';
import '../services/sensor_service.dart';
import '../widgets/sensor_widgets.dart';

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
  bool _highlightConsumed = false;

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
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
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
      if (e.status == EventStatus.confirmed ||
          e.status == EventStatus.falseAlarm) {
        continue;
      }
      return e;
    }
    return null;
  }

  Future<void> _openSensor(Sensor sensor) async {
    final event = _activeEventForSensor(sensor.id);
    if (event == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${sensor.type.label}: ${sensor.status.label}')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ManageEventSheet(event: event, sensor: sensor),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Датчики · администратор'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            for (int e = 1; e <= kEntrancesCount; e++) Tab(text: 'Подъезд $e'),
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
                        child: TabBarView(
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
                        onTap: () => onSensorTap(water),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AdminSensorTile(
                        sensor: smoke,
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

  const _AdminSensorTile({required this.sensor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = sensorStatusColor(sensor.status);
    final isAlert = sensor.status == SensorStatus.alert;

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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(sensorTypeIcon(sensor.type), color: color, size: 18),
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
                    sensor.status.label,
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
      ),
    );

    return PulsingAlert(active: isAlert, child: tile);
  }
}

class _ManageEventSheet extends StatefulWidget {
  final SensorEvent event;
  final Sensor sensor;

  const _ManageEventSheet({required this.event, required this.sensor});

  @override
  State<_ManageEventSheet> createState() => _ManageEventSheetState();
}

class _ManageEventSheetState extends State<_ManageEventSheet> {
  final SensorService _service = SensorService.instance;
  final TextEditingController _commentCtrl = TextEditingController();

  late EventStatus _status = widget.event.status;
  late ThreatType _threatType = widget.event.threatType ??
      (widget.event.type == SensorType.water
          ? ThreatType.waterLeak
          : ThreatType.fire);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _commentCtrl.text = widget.event.adminComment ?? '';
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({required bool notify}) async {
    if (_status == EventStatus.confirmed && _commentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте комментарий для подтверждения')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.updateEventStatus(
        eventId: widget.event.id,
        status: _status,
        threatType: _status == EventStatus.confirmed ? _threatType : null,
        adminComment: _status == EventStatus.confirmed
            ? _commentCtrl.text.trim()
            : null,
      );
      if (notify && _status == EventStatus.confirmed) {
        await _service.notifyEntrance(eventId: widget.event.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _status == EventStatus.falseAlarm
                ? 'Тревога закрыта'
                : notify
                    ? 'Статус обновлён, жильцы уведомлены'
                    : 'Статус обновлён',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConfirm = _status == EventStatus.confirmed;
    final isFalse = _status == EventStatus.falseAlarm;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + viewInsets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Управление событием',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(sensorTypeIcon(widget.sensor.type),
                            color: sensorStatusColor(widget.sensor.status)),
                        const SizedBox(width: 8),
                        Text(widget.sensor.type.label,
                            style: Theme.of(context).textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Подъезд ${widget.event.entranceNum} · этаж ${widget.event.floor}'),
                    const SizedBox(height: 4),
                    Text(
                      'Сработало ${formatSensorTime(widget.event.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Статус', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in EventStatus.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _status == s,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _status = s),
                  ),
              ],
            ),
            if (isConfirm) ...[
              const SizedBox(height: 16),
              Text('Тип угрозы', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Затопление'),
                      selected: _threatType == ThreatType.waterLeak,
                      onSelected: _saving
                          ? null
                          : (_) => setState(
                              () => _threatType = ThreatType.waterLeak),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Пожар'),
                      selected: _threatType == ThreatType.fire,
                      onSelected: _saving
                          ? null
                          : (_) =>
                              setState(() => _threatType = ThreatType.fire),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _commentCtrl,
                minLines: 2,
                maxLines: 4,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Комментарий',
                  hintText: 'Что увидели, какие действия предприняты',
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (isConfirm)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _save(notify: true),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Text(_saving
                      ? 'Сохраняем...'
                      : 'Подтвердить и уведомить жильцов'),
                ),
              )
            else if (isFalse)
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: _saving ? null : () => _save(notify: false),
                  child: Text(_saving ? 'Сохраняем...' : 'Закрыть как ложную'),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(notify: false),
                  child: Text(_saving ? 'Сохраняем...' : 'Сохранить статус'),
                ),
              ),
          ],
        ),
      ),
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
