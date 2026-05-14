import 'package:flutter/material.dart';

import '../services/api_client.dart';
import 'service_requests_page.dart' show specialtyLabel;

// ─────────────────────────────────────────────────────
// Admin: list of all staff members
// ─────────────────────────────────────────────────────

class _StaffInfo {
  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String specialty;
  final int inProgressCount;
  final int doneTodayCount;
  final DateTime? lastTakenAt;

  const _StaffInfo({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.specialty,
    required this.inProgressCount,
    required this.doneTodayCount,
    this.lastTakenAt,
  });

  factory _StaffInfo.fromMap(Map<String, dynamic> m) => _StaffInfo(
        id: (m['id'] ?? '').toString(),
        fullName: (m['full_name'] ?? '').toString(),
        email: (m['email'] ?? '').toString(),
        phone: (m['phone'] ?? '').toString(),
        specialty: (m['specialty'] ?? '').toString(),
        inProgressCount: (m['in_progress_count'] as num?)?.toInt() ?? 0,
        doneTodayCount: (m['done_today_count'] as num?)?.toInt() ?? 0,
        lastTakenAt: DateTime.tryParse((m['last_taken_at'] ?? '').toString()),
      );
}

class AdminStaffPage extends StatefulWidget {
  const AdminStaffPage({super.key});

  @override
  State<AdminStaffPage> createState() => _AdminStaffPageState();
}

class _AdminStaffPageState extends State<AdminStaffPage> {
  final ApiClient _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  List<_StaffInfo> _staff = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final res = await _api.get('/admin/staff');
      final list = (res.data as List)
          .map((m) => _StaffInfo.fromMap(Map<String, dynamic>.from(m as Map)))
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сотрудники')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : _staff.isEmpty
                  ? const Center(child: Text('Нет сотрудников'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _staff.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _StaffCard(
                          info: _staff[i],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StaffRequestsPage(
                                staffId: _staff[i].id,
                                staffName: _staff[i].fullName,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  final _StaffInfo info;
  final VoidCallback onTap;

  const _StaffCard({required this.info, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                child: Text(
                  info.fullName.isNotEmpty ? info.fullName[0] : '?',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.fullName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      specialtyLabel(info.specialty),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _CountBadge(
                          count: info.inProgressCount,
                          label: 'в работе',
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        _CountBadge(
                          count: info.doneTodayCount,
                          label: 'сегодня',
                          color: Colors.green,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _CountBadge({
    required this.count,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// Admin: requests assigned to a specific staff member
// ─────────────────────────────────────────────────────

class StaffRequestsPage extends StatefulWidget {
  final String staffId;
  final String staffName;

  const StaffRequestsPage({
    super.key,
    required this.staffId,
    required this.staffName,
  });

  @override
  State<StaffRequestsPage> createState() => _StaffRequestsPageState();
}

class _StaffRequestItem {
  final String id;
  final String category;
  final String description;
  final String status;
  final DateTime createdAt;
  final DateTime? takenAt;

  const _StaffRequestItem({
    required this.id,
    required this.category,
    required this.description,
    required this.status,
    required this.createdAt,
    this.takenAt,
  });

  factory _StaffRequestItem.fromMap(Map<String, dynamic> m) => _StaffRequestItem(
        id: (m['id'] ?? '').toString(),
        category: (m['category'] ?? '').toString(),
        description: (m['description'] ?? '').toString(),
        status: (m['status'] ?? 'new').toString(),
        createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()) ??
            DateTime.now(),
        takenAt: DateTime.tryParse((m['taken_at'] ?? '').toString()),
      );
}

class _StaffRequestsPageState extends State<StaffRequestsPage> {
  final ApiClient _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  List<_StaffRequestItem> _requests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final res = await _api.get('/admin/staff/${widget.staffId}/requests');
      final list = (res.data as List)
          .map((r) =>
              _StaffRequestItem.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
      if (!mounted) return;
      setState(() {
        _requests = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка: $e';
        _loading = false;
      });
    }
  }

  Color _statusColor(String s) => switch (s) {
        'in_progress' => Colors.orange,
        'done' => Colors.green,
        'rejected' => Colors.red,
        _ => Colors.grey,
      };

  String _statusLabel(String s) => switch (s) {
        'new' => 'Новая',
        'assigned' => 'Назначена',
        'in_progress' => 'В работе',
        'done' => 'Выполнено',
        'rejected' => 'Отклонено',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Заявки: ${widget.staffName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : _requests.isEmpty
                  ? const Center(child: Text('Нет заявок'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _requests.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final r = _requests[i];
                          final color = _statusColor(r.status);
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
                                          r.category,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          _statusLabel(r.status),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: color,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(r.description),
                                  const SizedBox(height: 6),
                                  Text(
                                    _fmt(r.createdAt),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  if (r.takenAt != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Взята: ${_fmt(r.takenAt!)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.grey[600]),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  static String _fmt(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year}  ${two(dt.hour)}:${two(dt.minute)}';
  }
}
