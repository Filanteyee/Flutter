import 'package:flutter/material.dart';

import '../models/sensor.dart';
import '../services/sensor_service.dart';

class AdminStatsPage extends StatefulWidget {
  const AdminStatsPage({super.key});

  @override
  State<AdminStatsPage> createState() => _AdminStatsPageState();
}

class _AdminStatsPageState extends State<AdminStatsPage> {
  final _service = SensorService.instance;
  String _period = 'today';
  bool _loading = true;
  String? _error;
  SensorStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await _service.getStats(period: _period);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка загрузки: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика датчиков'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'today', label: Text('Сегодня')),
                ButtonSegment(value: 'week', label: Text('Неделя')),
              ],
              selected: {_period},
              onSelectionChanged: (v) {
                setState(() => _period = v.first);
                _load();
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBody(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _StatsBody(stats: _stats!),
                ),
    );
  }
}

// ─── Тело страницы ──────────────────────────────────────────────────────────

class _StatsBody extends StatelessWidget {
  final SensorStats stats;
  const _StatsBody({required this.stats});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _KpiRow(stats: stats),
        const SizedBox(height: 16),
        const _SectionLabel(label: 'По статусам'),
        const SizedBox(height: 8),
        _ByStatusCard(byStatus: stats.byStatus, total: stats.totalEvents),
        if (stats.byThreat.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _SectionLabel(label: 'По типу угрозы'),
          const SizedBox(height: 8),
          _ByThreatCard(byThreat: stats.byThreat),
        ],
        if (stats.topFloors.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _SectionLabel(label: 'Топ этажей по событиям'),
          const SizedBox(height: 8),
          _TopFloorsCard(topFloors: stats.topFloors),
        ],
      ],
    );
  }
}

// ─── Вспомогательные виджеты ────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

// ─── KPI-карточки ───────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  final SensorStats stats;
  const _KpiRow({required this.stats});

  String _formatResponse(double seconds) {
    if (seconds <= 0) return '—';
    if (seconds < 60) return '${seconds.toInt()} сек';
    final m = seconds ~/ 60;
    final s = (seconds % 60).toInt();
    return s > 0 ? '$m мин $s с' : '$m мин';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final items = [
      (
        label: 'Событий',
        value: '${stats.totalEvents}',
        icon: Icons.notifications_outlined,
        color: primary,
      ),
      (
        label: 'Ср. реакция',
        value: _formatResponse(stats.avgResponseSeconds),
        icon: Icons.timer_outlined,
        color: Colors.blue,
      ),
      (
        label: 'Ложн. тревог',
        value: '${(stats.falseAlarmRate * 100).toStringAsFixed(0)}%',
        icon: Icons.cancel_outlined,
        color: Colors.orange,
      ),
      (
        label: 'Не на связи',
        value: '${stats.offlineSensors} / ${stats.totalSensors}',
        icon: Icons.cloud_off_outlined,
        color: Colors.grey,
      ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(items[i].icon, color: items[i].color, size: 20),
                    const SizedBox(height: 8),
                    Text(
                      items[i].value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: items[i].color,
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      items[i].label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── По статусам ────────────────────────────────────────────────────────────

Color _eventStatusColor(EventStatus status) {
  switch (status) {
    case EventStatus.detected:
      return Colors.orange;
    case EventStatus.checking:
      return Colors.blue;
    case EventStatus.confirmed:
      return Colors.red;
    case EventStatus.falseAlarm:
      return Colors.grey;
  }
}

Color _threatColor(ThreatType type) =>
    type == ThreatType.waterLeak ? Colors.blue : Colors.red;

class _ByStatusCard extends StatelessWidget {
  final Map<EventStatus, int> byStatus;
  final int total;
  const _ByStatusCard({required this.byStatus, required this.total});

  @override
  Widget build(BuildContext context) {
    if (byStatus.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Нет данных', style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    final entries = byStatus.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (int i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
              _BarRow(
                label: entries[i].key.label,
                count: entries[i].value,
                total: total,
                color: _eventStatusColor(entries[i].key),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ByThreatCard extends StatelessWidget {
  final Map<ThreatType, int> byThreat;
  const _ByThreatCard({required this.byThreat});

  @override
  Widget build(BuildContext context) {
    final total = byThreat.values.fold(0, (s, v) => s + v);
    final entries = byThreat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (int i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
              _BarRow(
                label: entries[i].key.label,
                count: entries[i].value,
                total: total,
                color: _threatColor(entries[i].key),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _BarRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = (total > 0 && count > 0) ? count / total : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text(
                '$count',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (ctx, constraints) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(
                    height: 6,
                    width: constraints.maxWidth,
                    color: color.withValues(alpha: 0.15),
                  ),
                  Container(
                    height: 6,
                    width: constraints.maxWidth * fraction,
                    color: color,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Топ этажей (Container-based bar chart) ─────────────────────────────────

class _TopFloorsCard extends StatelessWidget {
  final List<FloorCount> topFloors;
  const _TopFloorsCard({required this.topFloors});

  @override
  Widget build(BuildContext context) {
    final maxCount =
        topFloors.fold<int>(1, (m, f) => f.count > m ? f.count : m);
    final barColor = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            for (int i = 0; i < topFloors.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      'П${topFloors[i].entrance} Эт.${topFloors[i].floor}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (ctx, constraints) {
                        final w =
                            constraints.maxWidth * topFloors[i].count / maxCount;
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            children: [
                              Container(
                                height: 22,
                                width: constraints.maxWidth,
                                color: barColor.withValues(alpha: 0.1),
                              ),
                              Container(
                                height: 22,
                                width: w,
                                color: barColor.withValues(alpha: 0.7),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${topFloors[i].count}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Ошибка ─────────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBody({required this.message, required this.onRetry});

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
