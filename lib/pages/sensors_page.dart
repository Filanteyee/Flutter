import 'dart:async';

import 'package:flutter/material.dart';

import '../models/sensor.dart';
import '../services/auth_service.dart';
import '../services/sensor_service.dart';
import '../widgets/sensor_widgets.dart';
import 'sensor_event_detail_page.dart';

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
  Map<String, SensorEvent> _activeEventsMap = {};
  StreamSubscription<List<SensorEvent>>? _eventsSub;
  final Map<String, GlobalKey> _eventKeys = {};
  bool _highlightConsumed = false;

  /// Событие, по которому пришёл пуш, если оно ещё не CONFIRMED.
  /// Показываем отдельной «Активное срабатывание»-карточкой над списком,
  /// потому что список фильтрует только CONFIRMED.
  SensorEvent? _highlightEvent;

  @override
  void initState() {
    super.initState();
    _load();
    _eventsSub = _service.eventsStream.listen((events) {
      if (!mounted || _entrance == null) return;
      final entranceEvents =
          events.where((e) => e.entranceNum == _entrance!).toList();
      final displayEvents = entranceEvents
          .where((e) => e.status == EventStatus.confirmed)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final activeMap = <String, SensorEvent>{};
      for (final e in entranceEvents) {
        if (e.status != EventStatus.falseAlarm) {
          activeMap.putIfAbsent(e.sensorId, () => e);
        }
      }
      final hid = widget.highlightEventId;
      final hideHighlight = hid != null && displayEvents.any((e) => e.id == hid);
      setState(() {
        _events = displayEvents;
        _activeEventsMap = activeMap;
        if (hideHighlight) _highlightEvent = null;
      });
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
      // Загружаем все события — для окраски датчиков и для отображения.
      final allEvents = await _service.getEvents(entrance: address.entrance);
      final displayEvents = allEvents
          .where((e) => e.status == EventStatus.confirmed)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final activeMap = <String, SensorEvent>{};
      for (final e in allEvents) {
        if (e.status != EventStatus.falseAlarm) {
          activeMap.putIfAbsent(e.sensorId, () => e);
        }
      }

      // Если пришёл пуш по событию, которое ещё не CONFIRMED — показываем
      // «Активное срабатывание»-карточку сверху.
      SensorEvent? highlight;
      final hid = widget.highlightEventId;
      if (hid != null && !displayEvents.any((e) => e.id == hid)) {
        // Ищем среди загруженных событий
        SensorEvent? found;
        for (final e in allEvents) {
          if (e.id == hid) { found = e; break; }
        }
        if (found != null) {
          highlight = found;
        } else {
          try {
            final detail = await _service.getEventDetail(hid);
            highlight = detail.event;
          } catch (e) {
            debugPrint('[SensorsPage] getEventDetail($hid) failed: $e');
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _entrance = address.entrance;
        _floor = address.floor;
        _sensors = sensors;
        _events = displayEvents;
        _activeEventsMap = activeMap;
        _highlightEvent = highlight;
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

  SensorEvent? _activeEventForSensor(String sensorId) =>
      _activeEventsMap[sensorId];

  Future<void> _openEventDetail(String eventId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SensorEventDetailPage(eventId: eventId),
      ),
    );
    if (!mounted) return;
    _load();
  }

  void _openFloorDetails(int floor) {
    final water = _sensorFor(floor, SensorType.water);
    final smoke = _sensorFor(floor, SensorType.smoke);
    final waterEvent = water != null ? _activeEventForSensor(water.id) : null;
    final smokeEvent = smoke != null ? _activeEventForSensor(smoke.id) : null;
    final entrance = _entrance;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: SingleChildScrollView(
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
                  FloorSensorCard(sensor: water, activeEvent: waterEvent),
                const SizedBox(height: 12),
                if (smoke != null)
                  FloorSensorCard(sensor: smoke, activeEvent: smokeEvent),
              ],
              ),
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
                          waterEvent: () {
                            final s = _sensorFor(_floor!, SensorType.water);
                            return s != null ? _activeEventForSensor(s.id) : null;
                          }(),
                          smokeEvent: () {
                            final s = _sensorFor(_floor!, SensorType.smoke);
                            return s != null ? _activeEventForSensor(s.id) : null;
                          }(),
                        ),
                        const SizedBox(height: 22),
                        _SectionTitle('Подъезд ${_entrance!} — все этажи'),
                        const SizedBox(height: 10),
                        _AllFloorsList(
                          entrance: _entrance!,
                          currentFloor: _floor!,
                          sensors: _sensors,
                          activeEventsMap: _activeEventsMap,
                          onTap: _openFloorDetails,
                        ),
                        if (_highlightEvent != null) ...[
                          const SizedBox(height: 22),
                          const _SectionTitle('Активное срабатывание'),
                          const SizedBox(height: 10),
                          _PendingEventCard(
                            event: _highlightEvent!,
                            onTap: () => _openEventDetail(_highlightEvent!.id),
                          ),
                        ],
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
                                onTap: () => _openEventDetail(e.id),
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
  final SensorEvent? waterEvent;
  final SensorEvent? smokeEvent;

  const _MyFloorRow({
    required this.water,
    required this.smoke,
    this.waterEvent,
    this.smokeEvent,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: water == null
                ? const _MissingSensor(label: 'Датчик воды')
                : FloorSensorCard(sensor: water!, activeEvent: waterEvent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: smoke == null
                ? const _MissingSensor(label: 'Датчик дыма')
                : FloorSensorCard(sensor: smoke!, activeEvent: smokeEvent),
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
  final Map<String, SensorEvent> activeEventsMap;
  final ValueChanged<int> onTap;

  const _AllFloorsList({
    required this.entrance,
    required this.currentFloor,
    required this.sensors,
    required this.activeEventsMap,
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
      final wSensor = _sensorFor(f, SensorType.water);
      final sSensor = _sensorFor(f, SensorType.smoke);
      rows.add(
        FloorSummaryRow(
          floor: f,
          water: wSensor,
          smoke: sSensor,
          highlightCurrent: f == currentFloor,
          onTap: () => onTap(f),
          waterEvent: wSensor != null ? activeEventsMap[wSensor.id] : null,
          smokeEvent: sSensor != null ? activeEventsMap[sSensor.id] : null,
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
  final VoidCallback? onTap;

  const _ActiveEventCard({
    required this.event,
    this.highlighted = false,
    this.onTap,
  });

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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
      ),
    );
  }
}

/// Карточка для события, по которому пришёл пуш, но оно ещё не CONFIRMED.
/// Показывается над списком подтверждённых, чтобы тап по баннеру всегда
/// приводил к видимому индикатору на экране.
class _PendingEventCard extends StatelessWidget {
  final SensorEvent event;
  final VoidCallback? onTap;

  const _PendingEventCard({required this.event, this.onTap});

  @override
  Widget build(BuildContext context) {
    final threat = event.threatType ??
        (event.type == SensorType.water ? ThreatType.waterLeak : ThreatType.fire);
    const color = Colors.red;

    return PulsingAlert(
      active: event.status == EventStatus.detected,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.red, width: 2),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
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
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
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
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      event.status.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Администратор проверяет ситуацию. Информация обновится после подтверждения.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Сработало ${formatSensorTime(event.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
          ),
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
