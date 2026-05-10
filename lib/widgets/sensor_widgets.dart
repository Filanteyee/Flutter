import 'package:flutter/material.dart';

import '../models/sensor.dart';

Color sensorStatusColor(SensorStatus status) {
  switch (status) {
    case SensorStatus.normal:
      return Colors.green;
    case SensorStatus.alert:
      return Colors.red;
    case SensorStatus.offline:
      return Colors.grey;
  }
}

IconData sensorTypeIcon(SensorType type) {
  return type == SensorType.water
      ? Icons.water_drop_outlined
      : Icons.local_fire_department_outlined;
}

IconData threatIcon(ThreatType type) {
  return type == ThreatType.waterLeak
      ? Icons.water_damage_outlined
      : Icons.local_fire_department_outlined;
}

String formatSensorTime(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final diff = now.difference(local);
  if (diff.inMinutes < 1) return 'только что';
  if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
  if (diff.inHours < 24) return '${diff.inHours} ч назад';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}

/// Пульсирующая обёртка — opacity ходит между 0.4 и 1.0.
/// Используем для датчиков и плашек со статусом ALERT.
class PulsingAlert extends StatefulWidget {
  final Widget child;
  final bool active;

  const PulsingAlert({
    super.key,
    required this.child,
    this.active = true,
  });

  @override
  State<PulsingAlert> createState() => _PulsingAlertState();
}

class _PulsingAlertState extends State<PulsingAlert>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.active) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant PulsingAlert oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

/// Большая карточка для секции «Ваш этаж».
class FloorSensorCard extends StatelessWidget {
  final Sensor sensor;
  final VoidCallback? onTap;

  const FloorSensorCard({
    super.key,
    required this.sensor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = sensorStatusColor(sensor.status);
    final isAlert = sensor.status == SensorStatus.alert;

    final body = Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
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
                    child: Icon(sensorTypeIcon(sensor.type), color: color, size: 24),
                  ),
                  const Spacer(),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                sensor.type.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                sensor.status.label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Обновлено: ${formatSensorTime(sensor.lastUpdated)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );

    return PulsingAlert(active: isAlert, child: body);
  }
}

/// Компактная строка этажа со сводкой по двум датчикам.
class FloorSummaryRow extends StatelessWidget {
  final int floor;
  final Sensor? water;
  final Sensor? smoke;
  final bool highlightCurrent;
  final VoidCallback onTap;

  const FloorSummaryRow({
    super.key,
    required this.floor,
    required this.water,
    required this.smoke,
    required this.highlightCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: highlightCurrent
                      ? accent.withOpacity(0.18)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$floor',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: highlightCurrent ? accent : null,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  highlightCurrent ? 'Этаж $floor (ваш)' : 'Этаж $floor',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              _MiniSensorBadge(sensor: water),
              const SizedBox(width: 8),
              _MiniSensorBadge(sensor: smoke),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniSensorBadge extends StatelessWidget {
  final Sensor? sensor;

  const _MiniSensorBadge({required this.sensor});

  @override
  Widget build(BuildContext context) {
    if (sensor == null) {
      return const SizedBox(width: 28);
    }

    final color = sensorStatusColor(sensor!.status);
    final isAlert = sensor!.status == SensorStatus.alert;

    final badge = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(sensorTypeIcon(sensor!.type), color: color, size: 16),
    );

    return PulsingAlert(active: isAlert, child: badge);
  }
}
