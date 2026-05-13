import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sensor.dart';
import '../services/api_client.dart';
import '../services/sensor_service.dart';
import '../widgets/sensor_widgets.dart';

/// Детальная страница события: данные датчика, текущий статус, таймлайн
/// переходов (DETECTED → CHECKING → CONFIRMED/FALSE_ALARM) и админ-действия
/// внизу для роли `admin`.
class SensorEventDetailPage extends StatefulWidget {
  final String eventId;

  const SensorEventDetailPage({super.key, required this.eventId});

  @override
  State<SensorEventDetailPage> createState() => _SensorEventDetailPageState();
}

class _SensorEventDetailPageState extends State<SensorEventDetailPage> {
  final SensorService _service = SensorService.instance;

  bool _loading = true;
  String? _error;
  SensorEventDetail? _detail;
  bool _acting = false;

  bool get _isAdmin => ApiClient.instance.userRole == 'admin';

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
      final detail = await _service.getEventDetail(widget.eventId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить событие: $e';
        _loading = false;
      });
    }
  }

  Future<void> _markChecking() async {
    final d = _detail;
    if (d == null) return;
    await _patch(status: EventStatus.checking, successMsg: 'Помечено как «Проверяется»');
  }

  Future<void> _confirm() async {
    final d = _detail;
    if (d == null) return;
    final result = await showDialog<_ConfirmResult>(
      context: context,
      builder: (_) => _ConfirmDialog(
        initialThreat: d.event.threatType ??
            (d.event.type == SensorType.water
                ? ThreatType.waterLeak
                : ThreatType.fire),
        initialComment: d.event.adminComment ?? '',
      ),
    );
    if (result == null) return;
    await _patch(
      status: EventStatus.confirmed,
      threatType: result.threatType,
      comment: result.comment,
      successMsg: 'Тревога подтверждена и отправлена жильцам',
      notify: true,
    );
  }

  Future<void> _falseAlarm() async {
    final d = _detail;
    if (d == null) return;
    final comment = await showDialog<String>(
      context: context,
      builder: (_) => _CommentDialog(
        title: 'Ложная тревога',
        initial: d.event.adminComment ?? '',
        hint: 'Что именно сработало ложно',
      ),
    );
    if (comment == null) return;
    await _patch(
      status: EventStatus.falseAlarm,
      comment: comment.trim().isEmpty ? null : comment.trim(),
      successMsg: 'Закрыто как ложная тревога',
      alsoReset: true,
    );
  }

  Future<void> _resolveAlert() async {
    final d = _detail;
    if (d == null) return;
    setState(() => _acting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.resetSensor(d.sensor.id);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Тревога снята, датчик сброшен в норму')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Ошибка сброса: $e')));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  void _callServices(ThreatType threat) {
    final services = threat == ThreatType.fire
        ? [
            ('Пожарная служба', '101'),
            ('Скорая помощь', '103'),
            ('Полиция', '102'),
          ]
        : [
            ('Аварийная служба', '104'),
            ('Скорая помощь', '103'),
            ('УК (диспетчер)', '+7 727 000 0000'),
          ];
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Вызвать службы'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in services)
              ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: Text(s.$1),
                subtitle: Text(s.$2),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: s.$2));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Номер ${s.$2} скопирован')),
                  );
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> _patch({
    required EventStatus status,
    ThreatType? threatType,
    String? comment,
    required String successMsg,
    bool notify = false,
    bool alsoReset = false,
  }) async {
    setState(() => _acting = true);
    final messenger = ScaffoldMessenger.of(context);
    final sensorId = _detail?.sensor.id;
    try {
      await _service.updateEventStatus(
        eventId: widget.eventId,
        status: status,
        threatType: threatType,
        adminComment: comment,
      );
      if (notify) {
        try {
          await _service.notifyEntrance(eventId: widget.eventId);
        } catch (_) {}
      }
      if (alsoReset && sensorId != null) {
        try {
          await _service.resetSensor(sensorId);
        } catch (_) {}
      }
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(successMsg)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Событие датчика')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : _buildBody(_detail!),
      ),
    );
  }

  Widget _buildBody(SensorEventDetail d) {
    final threat = d.event.threatType ??
        (d.event.type == SensorType.water
            ? ThreatType.waterLeak
            : ThreatType.fire);
    final color = _colorFor(d.event.status);
    final isTerminal = d.event.status == EventStatus.falseAlarm;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: color.withValues(alpha: 0.45), width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(threatIcon(threat), color: color, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              threat.label,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Подъезд ${d.event.entranceNum} · этаж ${d.event.floor}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Датчик ${d.sensor.id}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          d.event.status.label,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                  if ((d.event.adminComment ?? '').isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Комментарий администратора',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(d.event.adminComment!),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'История',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _Timeline(steps: d.timeline),
          if (_isAdmin && !isTerminal) ...[
            const SizedBox(height: 24),
            Text(
              'Действия администратора',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (d.event.status == EventStatus.confirmed) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _acting ? null : _resolveAlert,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Тревога решена'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _acting ? null : () => _callServices(threat),
                  icon: const Icon(Icons.phone_outlined),
                  label: const Text('Вызвать службы'),
                ),
              ),
            ] else ...[
              if (d.event.status == EventStatus.detected)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _acting ? null : _markChecking,
                    icon: const Icon(Icons.search),
                    label: const Text('Принять в работу'),
                  ),
                ),
              if (d.event.status == EventStatus.detected) const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _acting ? null : _confirm,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Подтвердить и уведомить жильцов'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _acting ? null : _falseAlarm,
                  icon: const Icon(Icons.close_outlined),
                  label: const Text('Ложная тревога'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Color _colorFor(EventStatus s) {
    switch (s) {
      case EventStatus.detected:
        return Colors.red;
      case EventStatus.checking:
        return Colors.orange;
      case EventStatus.confirmed:
        return Colors.orange;
      case EventStatus.falseAlarm:
        return Colors.grey;
    }
  }
}

class _Timeline extends StatelessWidget {
  final List<TimelineStep> steps;

  const _Timeline({required this.steps});

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'История пуста',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < steps.length; i++)
              _TimelineRow(
                step: steps[i],
                isFirst: i == 0,
                isLast: i == steps.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final TimelineStep step;
  final bool isFirst;
  final bool isLast;

  const _TimelineRow({
    required this.step,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final color = _color(step.status);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 10,
                  color: isFirst
                      ? Colors.transparent
                      : Theme.of(context).dividerColor,
                ),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : Theme.of(context).dividerColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.status.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatSensorTime(step.at),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (step.threatType != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Угроза: ${step.threatType!.label}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if ((step.comment ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(step.comment!,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  if ((step.by ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Админ: ${_shortId(step.by!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _shortId(String uuid) {
    if (uuid.length <= 8) return uuid;
    return uuid.substring(0, 8);
  }

  Color _color(EventStatus s) {
    switch (s) {
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
}

class _ConfirmResult {
  final ThreatType threatType;
  final String comment;
  const _ConfirmResult(this.threatType, this.comment);
}

class _ConfirmDialog extends StatefulWidget {
  final ThreatType initialThreat;
  final String initialComment;

  const _ConfirmDialog({
    required this.initialThreat,
    required this.initialComment,
  });

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  late ThreatType _threat = widget.initialThreat;
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialComment);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Подтвердить тревогу'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Тип угрозы'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final t in ThreatType.values)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _threat == t,
                    onSelected: (_) => setState(() => _threat = t),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Комментарий',
                hintText: 'Что увидели, что делается',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final text = _ctrl.text.trim();
            if (text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Добавьте комментарий')),
              );
              return;
            }
            Navigator.pop(context, _ConfirmResult(_threat, text));
          },
          child: const Text('Подтвердить'),
        ),
      ],
    );
  }
}

class _CommentDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String hint;

  const _CommentDialog({
    required this.title,
    required this.initial,
    required this.hint,
  });

  @override
  State<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends State<_CommentDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Сохранить'),
        ),
      ],
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
