import 'package:flutter/material.dart';

import '../services/api_client.dart';
import 'announcements_page.dart';
import 'guests_page.dart';
import 'service_requests_page.dart' show buildPhotoUrl;

class ServiceInfo {
  final String title;
  final String subtitle;
  final IconData icon;
  final String staffName;
  final String phone;
  final String hours;
  final bool available;
  final String description;
  final List<String> categories;

  const ServiceInfo({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.staffName,
    required this.phone,
    required this.hours,
    required this.available,
    required this.description,
    required this.categories,
  });
}

const _kServices = [
  ServiceInfo(
    title: 'Сантехник',
    subtitle: 'Протечки, краны, трубы',
    icon: Icons.plumbing_outlined,
    staffName: 'Ахмет Бекжанов',
    phone: '+7 701 234 5678',
    hours: 'Пн–Пт, 09:00–18:00',
    available: true,
    description:
        'Устранение протечек, ремонт и замена кранов, труб и сантехнических приборов.',
    categories: ['Протечка'],
  ),
  ServiceInfo(
    title: 'Электрик',
    subtitle: 'Розетки, освещение, автоматы',
    icon: Icons.electrical_services_outlined,
    staffName: 'Бауыржан Сейткали',
    phone: '+7 702 345 6789',
    hours: 'Пн–Пт, 09:00–18:00',
    available: true,
    description:
        'Монтаж и ремонт электропроводки, розеток, выключателей и осветительных приборов.',
    categories: ['Электричество', 'Освещение'],
  ),
  ServiceInfo(
    title: 'Уборка',
    subtitle: 'Подъезд / двор / после ремонта',
    icon: Icons.cleaning_services_outlined,
    staffName: 'Гүлнар Ахметова',
    phone: '+7 703 456 7890',
    hours: 'Пн–Сб, 08:00–17:00',
    available: true,
    description:
        'Уборка подъездов, придомовой территории, мест общего пользования и послеремонтная уборка.',
    categories: ['Уборка'],
  ),
  ServiceInfo(
    title: 'Вывоз мусора',
    subtitle: 'Мусор, мебель, стройматериалы',
    icon: Icons.local_shipping_outlined,
    staffName: 'Нурлан Дюсенов',
    phone: '+7 704 567 8901',
    hours: 'Пн–Пт, 10:00–17:00',
    available: false,
    description:
        'Вывоз крупногабаритного мусора, старой мебели и строительных отходов.',
    categories: ['Другое'],
  ),
  ServiceInfo(
    title: 'Охрана',
    subtitle: 'Вопросы безопасности',
    icon: Icons.security_outlined,
    staffName: 'Дмитрий Карпов',
    phone: '+7 705 678 9012',
    hours: 'Круглосуточно',
    available: true,
    description:
        'Контроль доступа на территорию ЖК, видеонаблюдение, реагирование на вызовы.',
    categories: [],
  ),
  ServiceInfo(
    title: 'Домофон',
    subtitle: 'Ключи, доступ, трубка',
    icon: Icons.door_front_door_outlined,
    staffName: 'Арман Сейтханов',
    phone: '+7 706 789 0123',
    hours: 'Пн–Пт, 09:00–17:00',
    available: true,
    description:
        'Ремонт домофонного оборудования, изготовление дубликатов ключей и карт доступа.',
    categories: ['Домофон'],
  ),
  ServiceInfo(
    title: 'Ремонт лифтов',
    subtitle: 'Техническое обслуживание',
    icon: Icons.elevator_outlined,
    staffName: 'АО «Лифтсервис»',
    phone: '+7 800 123 4567',
    hours: 'Пн–Вс, аварийно 24/7',
    available: true,
    description:
        'Плановое техническое обслуживание и аварийный ремонт лифтового оборудования.',
    categories: ['Лифт'],
  ),
];

class ServicesPage extends StatelessWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сервисы')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _TopServiceCard(
                    title: 'Объявления',
                    subtitle: 'Новости от УК',
                    icon: Icons.campaign_outlined,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AnnouncementsPage()),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TopServiceCard(
                    title: 'Гости в ЖК',
                    subtitle: 'Оформить пропуск',
                    icon: Icons.badge_outlined,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GuestsPage()),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Службы ЖК',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ..._kServices.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: Icon(s.icon),
                    title: Text(s.title),
                    subtitle: Text(s.subtitle),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: s.available ? Colors.green : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServiceDetailPage(service: s),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopServiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _TopServiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Детальная страница службы: информация о сотруднике + заявки по категории.
// ─────────────────────────────────────────────────────────────────────────────

class ServiceDetailPage extends StatefulWidget {
  final ServiceInfo service;

  const ServiceDetailPage({super.key, required this.service});

  @override
  State<ServiceDetailPage> createState() => _ServiceDetailPageState();
}

class _ServiceDetailPageState extends State<ServiceDetailPage> {
  final ApiClient _api = ApiClient.instance;

  bool get _isAdmin => _api.userRole == 'admin';

  bool _loading = true;
  String? _error;
  List<_SvcRequest> _requests = [];

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
      if (!_api.isLoggedIn) {
        setState(() {
          _requests = [];
          _loading = false;
        });
        return;
      }
      final res = await _api.get('/service-requests');
      final all = (res.data as List)
          .map((r) => _SvcRequest.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();

      final cats = widget.service.categories;
      final filtered = cats.isEmpty
          ? all
          : all.where((r) => cats.contains(r.category)).toList();
      filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() {
        _requests = filtered;
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

  Future<void> _changeStatus(_SvcRequest req, String status) async {
    try {
      await _api.put('/service-requests/${req.id}', data: {'status': status});
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Статус обновлён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return Scaffold(
      appBar: AppBar(title: Text(s.title)),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Карточка сотрудника ─────────────────────────────────────
              Card(
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(s.icon,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.staffName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: s.available
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      s.available ? 'Доступен' : 'Недоступен',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: s.available
                                                ? Colors.green
                                                : Colors.grey,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _InfoRow(
                          icon: Icons.phone_outlined, text: s.phone),
                      const SizedBox(height: 8),
                      _InfoRow(
                          icon: Icons.access_time_outlined,
                          text: s.hours),
                      const SizedBox(height: 8),
                      _InfoRow(
                          icon: Icons.info_outline, text: s.description),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.service.categories.isEmpty
                    ? 'Все заявки'
                    : 'Заявки: ${widget.service.categories.join(', ')}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator()))
              else if (_error != null)
                _ErrorCard(message: _error!, onRetry: _load)
              else if (_requests.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Заявок по этой теме пока нет',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              else
                ..._requests.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SvcRequestCard(
                      request: r,
                      isAdmin: _isAdmin,
                      onStatusChanged: (status) => _changeStatus(r, status),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _SvcRequest {
  final String id;
  final String category;
  final String description;
  final String status;
  final DateTime createdAt;
  final List<String> photos;

  const _SvcRequest({
    required this.id,
    required this.category,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.photos,
  });

  factory _SvcRequest.fromMap(Map<String, dynamic> m) {
    final photosRaw = m['photos'];
    final photos = <String>[];
    if (photosRaw is List) {
      for (final p in photosRaw) {
        if (p != null) photos.add(p.toString());
      }
    }
    return _SvcRequest(
      id: (m['id'] ?? '').toString(),
      category: (m['category'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      status: (m['status'] ?? 'new').toString(),
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()) ??
          DateTime.now(),
      photos: photos,
    );
  }
}

class _SvcRequestCard extends StatelessWidget {
  final _SvcRequest request;
  final bool isAdmin;
  final ValueChanged<String> onStatusChanged;

  const _SvcRequestCard({
    required this.request,
    required this.isAdmin,
    required this.onStatusChanged,
  });

  Color _statusColor(String s) {
    switch (s) {
      case 'done':
        return Colors.green;
      case 'in_progress':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  String _statusLabel(String s) => switch (s) {
        'new' => 'Новая',
        'in_progress' => 'В работе',
        'done' => 'Выполнено',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(request.status);
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
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusLabel(request.status),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(request.description),
            const SizedBox(height: 8),
            Text(
              _formatDate(request.createdAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (request.photos.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: request.photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      buildPhotoUrl(request.photos[i]),
                      headers: ApiClient.instance.token != null
                          ? {
                              'Authorization':
                                  'Bearer ${ApiClient.instance.token}'
                            }
                          : null,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 80,
                        height: 80,
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
            if (isAdmin) ...[
              const SizedBox(height: 10),
              PopupMenuButton<String>(
                tooltip: 'Изменить статус',
                onSelected: onStatusChanged,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'new', child: Text('Новая')),
                  PopupMenuItem(
                      value: 'in_progress', child: Text('В работе')),
                  PopupMenuItem(value: 'done', child: Text('Выполнено')),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text('Изменить статус',
                        style: Theme.of(context).textTheme.labelMedium),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year}  ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(message),
            const SizedBox(height: 10),
            FilledButton.tonal(
                onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}
