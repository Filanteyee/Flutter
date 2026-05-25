import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../widgets/create_request_sheet.dart';

String buildPhotoUrl(String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    if (!kIsWeb) {
      final serverHost = Uri.parse(ApiClient.baseHost).host;
      return path
          .replaceFirst('http://localhost:', 'http://$serverHost:')
          .replaceFirst('https://localhost:', 'https://$serverHost:');
    }
    return path;
  }
  final host = ApiClient.baseHost;
  return path.startsWith('/') ? '$host$path' : '$host/$path';
}

String specialtyLabel(String specialty) => switch (specialty) {
      'plumbing' => 'Сантехник',
      'electrical' => 'Электрик',
      'cleaning' => 'Уборка',
      'garbage' => 'Вывоз мусора',
      'intercom' => 'Домофон',
      'elevator' => 'Ремонт лифтов',
      _ => specialty,
    };

class ServiceRequestsPage extends StatefulWidget {
  final String? prefilledTitle;
  const ServiceRequestsPage({super.key, this.prefilledTitle});

  @override
  State<ServiceRequestsPage> createState() => _ServiceRequestsPageState();
}

class _ServiceRequestsPageState extends State<ServiceRequestsPage> {
  final ApiClient _api = ApiClient.instance;

  bool get _isAdmin => _api.userRole == 'admin';
  bool get _isStaff => _api.userRole == 'staff';

  String _query = '';
  String? _filter;
  bool _loading = true;
  String? _error;
  List<_RequestItem> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
    if (widget.prefilledTitle != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showCreateSheet());
    }
  }

  Future<void> _showCreateSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CreateRequestSheet(prefilledDescription: widget.prefilledTitle),
    );
    await _loadRequests();
  }

  Future<void> _loadRequests() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      if (!_api.isLoggedIn) {
        setState(() {
          _requests = [];
          _loading = false;
        });
        return;
      }
      final res = await _api.get('/service-requests');
      final items = (res.data as List)
          .map((row) =>
              _RequestItem.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
      if (!mounted) return;
      setState(() {
        _requests = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка загрузки заявок: $e';
        _loading = false;
      });
    }
  }

  Future<void> _changeStatus(_RequestItem request, String status) async {
    try {
      await _api.put('/service-requests/${request.id}', data: {'status': status});
      await _loadRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Статус заявки обновлён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка обновления статуса: $e')),
      );
    }
  }

  Future<void> _takeRequest(String id) async {
    try {
      await _api.patch('/service-requests/$id/take');
      await _loadRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заявка взята в работу')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _resolveAppeal(String id, bool approved) async {
    try {
      await _api.post(
        '/admin/service-requests/$id/resolve-appeal',
        data: {'approved': approved},
      );
      await _loadRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approved ? 'Пропуск одобрен' : 'Апелляция отклонена'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _showAssignSheet(_RequestItem request) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _AssignStaffSheet(
        requestId: request.id,
        onAssigned: () => Navigator.pop(ctx),
      ),
    );
    await _loadRequests();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _requests.where((r) {
      final q = _query.trim().toLowerCase();
      final matchesQuery = q.isEmpty ||
          r.category.toLowerCase().contains(q) ||
          r.description.toLowerCase().contains(q);
      final matchesFilter = switch (_filter) {
        null => true,
        'new' => r.status == 'new' || r.status == 'assigned',
        'in_progress' => r.status == 'in_progress',
        'done' => r.status == 'done' || r.status == 'rejected',
        _ => r.status == _filter,
      };
      return matchesQuery && matchesFilter;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Заявки')),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Поиск по заявкам…',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('Все')),
                  ButtonSegment(value: 'new', label: Text('Новые')),
                  ButtonSegment(value: 'in_progress', label: Text('В работе')),
                  ButtonSegment(value: 'done', label: Text('Готово')),
                ],
                selected: {_filter},
                onSelectionChanged: (set) =>
                    setState(() => _filter = set.first),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _RequestsError(
                          message: _error!, onRetry: _loadRequests)
                      : filtered.isEmpty
                          ? const _EmptyRequests()
                          : RefreshIndicator(
                              onRefresh: _loadRequests,
                              child: ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, i) => _RequestCard(
                                  request: filtered[i],
                                  isAdmin: _isAdmin,
                                  isStaff: _isStaff,
                                  currentUserId: _api.userId,
                                  onStatusChanged: (status) =>
                                      _changeStatus(filtered[i], status),
                                  onTake: () => _takeRequest(filtered[i].id),
                                  onDone: () =>
                                      _changeStatus(filtered[i], 'done'),
                                  onReject: () =>
                                      _changeStatus(filtered[i], 'rejected'),
                                  onAssign: () =>
                                      _showAssignSheet(filtered[i]),
                                  onResolveAppeal: _isAdmin
                                      ? (approved) => _resolveAppeal(
                                            filtered[i].id, approved)
                                      : null,
                                ),
                              ),
                            ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isStaff
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => const CreateRequestSheet(),
                );
                await _loadRequests();
              },
              icon: const Icon(Icons.add),
              label: const Text('Создать'),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────

class _RequestItem {
  final String id;
  final String userId;
  final String category;
  final String description;
  final String status;
  final String? assignedTo;
  final String? assignedToName;
  final DateTime? takenAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<String> photoPaths;

  const _RequestItem({
    required this.id,
    required this.userId,
    required this.category,
    required this.description,
    required this.status,
    this.assignedTo,
    this.assignedToName,
    this.takenAt,
    required this.createdAt,
    required this.updatedAt,
    required this.photoPaths,
  });

  factory _RequestItem.fromMap(Map<String, dynamic> map) {
    final photosRaw = map['photos'];
    final photoPaths = <String>[];
    if (photosRaw is List) {
      for (final p in photosRaw) {
        if (p != null) photoPaths.add(p.toString());
      }
    }
    return _RequestItem(
      id: (map['id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      status: (map['status'] ?? 'new').toString(),
      assignedTo: map['assigned_to']?.toString(),
      assignedToName: map['assigned_to_name']?.toString(),
      takenAt: DateTime.tryParse((map['taken_at'] ?? '').toString()),
      createdAt: DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
      updatedAt: DateTime.tryParse((map['updated_at'] ?? '').toString()),
      photoPaths: photoPaths,
    );
  }
}

// ─────────────────────────────────────────────────────
// Request card
// ─────────────────────────────────────────────────────

class _RequestCard extends StatelessWidget {
  final _RequestItem request;
  final bool isAdmin;
  final bool isStaff;
  final String? currentUserId;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onTake;
  final VoidCallback onDone;
  final VoidCallback onReject;
  final VoidCallback onAssign;
  final void Function(bool approved)? onResolveAppeal;

  const _RequestCard({
    required this.request,
    required this.isAdmin,
    required this.isStaff,
    required this.currentUserId,
    required this.onStatusChanged,
    required this.onTake,
    required this.onDone,
    required this.onReject,
    required this.onAssign,
    this.onResolveAppeal,
  });

  bool get _canTake =>
      isStaff && (request.status == 'new' || request.status == 'assigned');

  bool get _canComplete =>
      isStaff &&
      currentUserId != null &&
      request.assignedTo != null &&
      request.assignedTo == currentUserId &&
      request.status == 'in_progress';

  bool get _canAssign => isAdmin && request.status == 'new';

  bool get _isParkingAppeal =>
      request.description.contains('Апелляция по паркингу');

  bool get _canResolveAppeal =>
      onResolveAppeal != null &&
      isAdmin &&
      _isParkingAppeal &&
      request.status != 'done' &&
      request.status != 'rejected';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.category,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusChip(status: request.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(request.description),
            if (isAdmin && request.assignedToName != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Назначено: ${request.assignedToName}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  if (request.takenAt != null) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.access_time,
                        size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      _fmt(request.takenAt!),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 12),
            _StatusTimeline(status: request.status),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  _fmt(request.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                if (isAdmin)
                  PopupMenuButton<String>(
                    tooltip: 'Изменить статус',
                    onSelected: onStatusChanged,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'new', child: Text('Новая')),
                      PopupMenuItem(
                          value: 'assigned', child: Text('Назначена')),
                      PopupMenuItem(
                          value: 'in_progress', child: Text('В работе')),
                      PopupMenuItem(value: 'done', child: Text('Выполнено')),
                      PopupMenuItem(
                          value: 'rejected', child: Text('Отклонено')),
                    ],
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.more_horiz),
                        SizedBox(width: 6),
                        Text('Статус'),
                      ],
                    ),
                  ),
              ],
            ),
            if (_canAssign) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onAssign,
                  icon: const Icon(Icons.assignment_ind_outlined, size: 18),
                  label: const Text('Назначить сотруднику'),
                ),
              ),
            ],
            if (_canTake) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onTake,
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: const Text('Взять в работу'),
                ),
              ),
            ],
            if (_canComplete) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onDone,
                      icon: const Icon(Icons.check),
                      label: const Text('Выполнено'),
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.green),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close),
                      label: const Text('Отклонить'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
            if (request.photoPaths.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: request.photoPaths.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      buildPhotoUrl(request.photoPaths[i]),
                      headers: ApiClient.instance.token != null
                          ? {
                              'Authorization':
                                  'Bearer ${ApiClient.instance.token}'
                            }
                          : null,
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 92,
                        height: 92,
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image,
                            color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (_canResolveAppeal) ...[
              const Divider(height: 20),
              Text(
                'Апелляция по паркингу',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.orange[800]),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => onResolveAppeal!(true),
                      icon: const Icon(Icons.check),
                      label: const Text('Одобрить пропуск'),
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.green),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onResolveAppeal!(false),
                      icon: const Icon(Icons.close),
                      label: const Text('Отклонить'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red),
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

  static String _fmt(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year}  ${two(dt.hour)}:${two(dt.minute)}';
  }
}

// ─────────────────────────────────────────────────────
// Status chip with color
// ─────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  String _text(String v) => switch (v) {
        'new' => 'Новая',
        'assigned' => 'Назначена',
        'in_progress' => 'В работе',
        'done' => 'Выполнено',
        'rejected' => 'Отклонено',
        _ => v,
      };

  IconData _icon(String v) => switch (v) {
        'new' => Icons.fiber_new,
        'assigned' => Icons.assignment_ind_outlined,
        'in_progress' => Icons.timelapse,
        'done' => Icons.check_circle,
        'rejected' => Icons.cancel,
        _ => Icons.help_outline,
      };

  Color _color(String v) => switch (v) {
        'in_progress' => Colors.orange,
        'done' => Colors.green,
        'rejected' => Colors.red,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color(status);
    return Chip(
      avatar: Icon(_icon(status), size: 18, color: color),
      label: Text(_text(status),
          style: TextStyle(color: color, fontSize: 12)),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ─────────────────────────────────────────────────────
// Status timeline
// ─────────────────────────────────────────────────────

class _StatusTimeline extends StatelessWidget {
  final String status;
  const _StatusTimeline({required this.status});

  bool get _step1 => true;
  bool get _step2 =>
      status == 'in_progress' || status == 'done' || status == 'rejected';
  bool get _step3 => status == 'done' || status == 'rejected';
  bool get _isRejected => status == 'rejected';

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted =
        Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5);
    final step3Color = _isRejected ? Colors.red : Colors.green;

    Widget dot(bool active, {Color? color}) => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? (color ?? primary) : muted,
          ),
        );
    Widget line(bool active) => Expanded(
          child: Container(height: 2, color: active ? primary : muted),
        );
    TextStyle labelStyle(bool active, {Color? color}) => TextStyle(
          fontSize: 12,
          color: active ? (color ?? primary) : muted,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          dot(_step1),
          line(_step2),
          dot(_step2),
          line(_step3),
          dot(_step3, color: step3Color),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text('Создано', style: labelStyle(_step1))),
          Expanded(
            child: Center(
                child: Text('В работе', style: labelStyle(_step2))),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _isRejected ? 'Отклонено' : 'Готово',
                style: labelStyle(_step3, color: step3Color),
              ),
            ),
          ),
        ]),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────
// Assign staff bottom sheet (admin)
// ─────────────────────────────────────────────────────

class _StaffMember {
  final String id;
  final String fullName;
  final String specialty;
  final int inProgressCount;

  const _StaffMember({
    required this.id,
    required this.fullName,
    required this.specialty,
    required this.inProgressCount,
  });

  factory _StaffMember.fromMap(Map<String, dynamic> m) => _StaffMember(
        id: (m['id'] ?? '').toString(),
        fullName: (m['full_name'] ?? '').toString(),
        specialty: (m['specialty'] ?? '').toString(),
        inProgressCount: (m['in_progress_count'] as num?)?.toInt() ?? 0,
      );
}

class _AssignStaffSheet extends StatefulWidget {
  final String requestId;
  final VoidCallback onAssigned;

  const _AssignStaffSheet({
    required this.requestId,
    required this.onAssigned,
  });

  @override
  State<_AssignStaffSheet> createState() => _AssignStaffSheetState();
}

class _AssignStaffSheetState extends State<_AssignStaffSheet> {
  final ApiClient _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  List<_StaffMember> _staff = [];
  String? _assigning;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _api.get('/admin/staff');
      final list = (res.data as List)
          .map((m) =>
              _StaffMember.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList();
      if (!mounted) return;
      setState(() {
        _staff = list;
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

  Future<void> _assign(String staffId) async {
    setState(() => _assigning = staffId);
    try {
      await _api.post(
        '/admin/service-requests/${widget.requestId}/assign',
        data: {'staff_id': staffId},
      );
      widget.onAssigned();
    } catch (e) {
      if (!mounted) return;
      setState(() => _assigning = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка назначения: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Назначить сотрудника',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!),
            )
          else if (_staff.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Нет доступных сотрудников'),
            )
          else
            ...(_staff.map((s) {
              final busy = _assigning == s.id;
              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    s.fullName.isNotEmpty ? s.fullName[0] : '?',
                  ),
                ),
                title: Text(s.fullName),
                subtitle: Text(
                  '${specialtyLabel(s.specialty)} · в работе: ${s.inProgressCount}',
                ),
                trailing: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _assigning != null ? null : () => _assign(s.id),
              );
            })),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────

class _EmptyRequests extends StatelessWidget {
  const _EmptyRequests();
  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Заявок нет. Нажми "Создать".'));
}

class _RequestsError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _RequestsError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}
