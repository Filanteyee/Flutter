import 'dart:async';

import 'package:flutter/material.dart';

import '../models/sensor.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/notifications_service.dart';
import '../services/sensor_service.dart';
import '../services/sse_service.dart';
import '../widgets/sensor_widgets.dart';
import 'admin_sensors_page.dart';
import 'admin_verification_page.dart';
import 'announcements_page.dart';
import 'barrier_page.dart';
import 'guests_page.dart';
import 'notifications_history_page.dart';
import 'payments_page.dart';
import 'profile_page.dart';
import 'sensors_page.dart';
import 'service_requests_page.dart';
import 'services_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  final ApiClient _api = ApiClient.instance;

  int _index = 0;
  bool _loadingRole = true;
  String _role = 'resident';
  bool _isLoggedIn = false;
  String _verificationStatus = 'not_submitted';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRole();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadRole();
    }
  }

  Future<void> _loadRole() async {
    try {
      if (!_api.isLoggedIn) {
        setState(() {
          _role = 'resident';
          _isLoggedIn = false;
          _verificationStatus = 'not_submitted';
          _loadingRole = false;
        });
        return;
      }
      final res = await _api.get('/auth/me');
      final role = (res.data['role'] ?? 'resident').toString();
      final verification =
          (res.data['verification_status'] ?? 'not_submitted').toString();
      await _api.updateRole(role);
      if (!mounted) return;
      setState(() {
        _role = role;
        _isLoggedIn = true;
        _verificationStatus = verification;
        _loadingRole = false;
      });
      // SSE-стрим только для админа — резидент пользуется FCM-пушами.
      if (role == 'admin') {
        SensorService.instance.attachSse(SseService.instance);
        SseService.instance.connect();
      } else {
        SseService.instance.disconnect();
        SensorService.instance.detachSse();
      }
      _consumePendingNotification();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _role = 'resident';
        _isLoggedIn = false;
        _verificationStatus = 'not_submitted';
        _loadingRole = false;
      });
    }
  }

  void _consumePendingNotification() {
    if (!mounted || !_isLoggedIn) return;
    final data = NotificationsService.instance.consumePendingOpenedMessage();
    if (data == null) return;
    if (data['kind'] != 'sensor_alert') return;
    final eventId = data['event_id'];
    final isAdmin = _role == 'admin';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isAdmin
            ? AdminSensorsPage(highlightEventId: eventId)
            : SensorsPage(highlightEventId: eventId),
      ),
    );
  }

  List<Widget> get _pages => [
    _HomeOverviewTab(
      role: _role,
      isLoggedIn: _isLoggedIn,
      verificationStatus: _verificationStatus,
      onRefresh: _loadRole,
    ),
    const ServiceRequestsPage(),
    const ServicesPage(),
    const PaymentsPage(),
    const ProfilePage(),
  ];

  List<BottomNavigationBarItem> get _items => const [
    BottomNavigationBarItem(
      icon: Icon(Icons.home_outlined),
      label: 'Главная',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.build_outlined),
      label: 'Заявки',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.grid_view_outlined),
      label: 'Сервисы',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.receipt_long_outlined),
      label: 'Платежи',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.person_outline),
      label: 'Профиль',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        items: _items,
        type: BottomNavigationBarType.fixed,
        onTap: (i) {
          setState(() => _index = i);
          // При возврате на главную перечитываем роль и статус верификации,
          // чтобы карточка датчиков сразу отразила свежее решение админа.
          if (i == 0) _loadRole();
        },
      ),
    );
  }

}

class _HomeOverviewTab extends StatelessWidget {
  final String role;
  final bool isLoggedIn;
  final String verificationStatus;
  final Future<void> Function() onRefresh;

  const _HomeOverviewTab({
    required this.role,
    required this.isLoggedIn,
    required this.verificationStatus,
    required this.onRefresh,
  });

  bool get _isAdmin => role == 'admin';
  bool get _isApprovedResident => verificationStatus == 'approved';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isAdmin ? 'Панель администратора' : 'Главная'),
        actions: [
          if (isLoggedIn)
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'История уведомлений',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationsHistoryPage(),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 6),
          Text(
            _isAdmin
                ? 'Управление заявками, проверкой документов и основными функциями жилого комплекса'
                : 'Сервис и удобство жилого комплекса',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          if (_isAdmin) ...[
            Row(
              children: [
                Expanded(
                  child: _TopActionButton(
                    label: 'Все заявки',
                    icon: Icons.assignment_outlined,
                    tonal: false,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ServiceRequestsPage(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TopActionButton(
                    label: 'Проверка',
                    icon: Icons.fact_check_outlined,
                    tonal: true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminVerificationPage(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const _SensorsStatusCard(mode: _SensorsCardMode.admin),
            const SizedBox(height: 14),
            _ActionGrid(
              children: [
                _ActionCard(
                  title: 'Управление заявками',
                  subtitle: '',
                  icon: Icons.build_circle_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ServiceRequestsPage(),
                      ),
                    );
                  },
                ),
                _ActionCard(
                  title: 'Проверка документов',
                  subtitle: '',
                  icon: Icons.verified_user_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminVerificationPage(),
                      ),
                    );
                  },
                ),
                _ActionCard(
                  title: 'Шлагбаум',
                  subtitle: 'История открытий и имитация IoT',
                  icon: Icons.garage_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BarrierPage(),
                      ),
                    );
                  },
                ),
                _ActionCard(
                  title: 'Объявления',
                  subtitle: 'Новости для жителей',
                  icon: Icons.campaign_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AnnouncementsPage(),
                      ),
                    );
                  },
                ),
                _ActionCard(
                  title: 'Профиль',
                  subtitle: 'Данные текущего администратора',
                  icon: Icons.person_outline,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProfilePage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ] else ...[
            // Жилец/Гость: верхняя строка кнопок и блок датчиков ниже.
            Row(
              children: [
                Expanded(
                  child: _TopActionButton(
                    label: 'Создать заявку',
                    icon: Icons.add_circle_outline,
                    tonal: true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ServiceRequestsPage(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TopActionButton(
                    label: 'Сервисы',
                    icon: Icons.grid_view_outlined,
                    tonal: false,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ServicesPage(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SensorsStatusCard(
              mode: !isLoggedIn
                  ? _SensorsCardMode.guest
                  : _isApprovedResident
                      ? _SensorsCardMode.resident
                      : _SensorsCardMode.unverified,
            ),
            const SizedBox(height: 14),
            _ActionGrid(
              children: [
                _ActionCard(
                  title: 'Объявления',
                  subtitle: 'Новости от УК',
                  icon: Icons.campaign_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AnnouncementsPage(),
                      ),
                    );
                  },
                ),
                _ActionCard(
                  title: 'Гости в ЖК',
                  subtitle: 'Пропуск и код для доступа',
                  icon: Icons.badge_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GuestsPage(),
                      ),
                    );
                  },
                ),
                _ActionCard(
                  title: 'Шлагбаум',
                  subtitle: 'Открыть въезд и посмотреть историю',
                  icon: Icons.garage_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BarrierPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ],
      ),
      ),
    ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool tonal;
  final VoidCallback onTap;

  const _TopActionButton({
    required this.label,
    required this.icon,
    required this.tonal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final button = tonal
        ? FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(
        label,
        maxLines: 2,
        textAlign: TextAlign.center,
      ),
    )
        : FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(
        label,
        maxLines: 2,
        textAlign: TextAlign.center,
      ),
    );

    return SizedBox(
      height: 64,
      child: button,
    );
  }
}

class _ActionGrid extends StatelessWidget {
  final List<Widget> children;

  const _ActionGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    for (int i = 0; i < children.length; i += 2) {
      final left = children[i];
      final right = i + 1 < children.length ? children[i + 1] : null;

      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              const SizedBox(width: 12),
              Expanded(child: right ?? const SizedBox()),
            ],
          ),
        ),
      );

      if (i + 2 < children.length) {
        rows.add(const SizedBox(height: 12));
      }
    }

    return Column(children: rows);
  }
}

enum _SensorsCardMode { admin, resident, unverified, guest }

class _SensorsStatusCard extends StatefulWidget {
  final _SensorsCardMode mode;

  const _SensorsStatusCard({required this.mode});

  @override
  State<_SensorsStatusCard> createState() => _SensorsStatusCardState();
}

class _SensorsStatusCardState extends State<_SensorsStatusCard> {
  final SensorService _service = SensorService.instance;

  bool _loading = true;
  bool _hasAlert = false;
  int? _entrance;
  int _offlineCount = 0;
  StreamSubscription<List<SensorEvent>>? _eventsSub;
  StreamSubscription<List<Sensor>>? _sensorsSub;

  bool get _interactive =>
      widget.mode == _SensorsCardMode.admin ||
      widget.mode == _SensorsCardMode.resident;

  @override
  void initState() {
    super.initState();
    if (_interactive) {
      _load();
      _eventsSub = _service.eventsStream.listen((events) {
        if (!mounted) return;
        final relevant = events.where((e) {
          if (e.status == EventStatus.falseAlarm ||
              e.status == EventStatus.confirmed) return false;
          if (widget.mode == _SensorsCardMode.admin) return true;
          return _entrance != null && e.entranceNum == _entrance;
        });
        setState(() => _hasAlert = relevant.isNotEmpty);
      });
      if (widget.mode == _SensorsCardMode.admin) {
        _offlineCount = _service.sensorsSnapshot
            .where((s) => s.status == SensorStatus.offline)
            .length;
        _sensorsSub = _service.sensorsStream.listen((sensors) {
          if (!mounted) return;
          setState(() => _offlineCount = sensors
              .where((s) => s.status == SensorStatus.offline)
              .length);
        });
      }
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _sensorsSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SensorsStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      if (_interactive) {
        setState(() => _loading = true);
        _load();
      } else {
        setState(() {
          _loading = false;
          _hasAlert = false;
        });
      }
    }
  }

  Future<void> _load() async {
    try {
      int? entrance;
      if (widget.mode == _SensorsCardMode.resident) {
        final address = await AuthService().getResidentAddress();
        entrance = address?.entrance;
      }
      if (widget.mode == _SensorsCardMode.admin) {
        final sensors = await _service.getAllSensors();
        if (mounted) {
          setState(() => _offlineCount = sensors
              .where((s) => s.status == SensorStatus.offline)
              .length);
        }
      }
      final events = await _service.getEvents(
        entrance: widget.mode == _SensorsCardMode.admin ? null : entrance,
      );
      final hasAlert = events.any((e) {
        if (e.status == EventStatus.falseAlarm ||
            e.status == EventStatus.confirmed) return false;
        if (widget.mode == _SensorsCardMode.admin) return true;
        return entrance == null || e.entranceNum == entrance;
      });
      if (!mounted) return;
      setState(() {
        _entrance = entrance;
        _hasAlert = hasAlert;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _open() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => widget.mode == _SensorsCardMode.admin
            ? const AdminSensorsPage()
            : const SensorsPage(),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final disabled = !_interactive;

    final Color color;
    final IconData icon;
    final String title;
    final String subtitle;

    if (widget.mode == _SensorsCardMode.guest) {
      color = Colors.grey;
      icon = Icons.lock_outline;
      title = 'Доступно после входа';
      subtitle = 'Войдите в аккаунт, чтобы видеть состояние датчиков';
    } else if (widget.mode == _SensorsCardMode.unverified) {
      color = Colors.grey;
      icon = Icons.verified_user_outlined;
      title = 'Подтвердите статус';
      subtitle =
          'Отправьте документы и адрес квартиры — после проверки появится доступ';
    } else if (widget.mode == _SensorsCardMode.resident && _entrance == null) {
      // Подтверждён, но локально не сохранён адрес — попросим повторить шаг.
      color = Colors.grey;
      icon = Icons.edit_location_alt_outlined;
      title = 'Укажите подъезд и квартиру';
      subtitle = 'Откройте «Подтвердить статус» и заполните адрес';
    } else {
      color = _hasAlert ? Colors.red : Colors.green;
      icon = _hasAlert ? Icons.warning_amber_rounded : Icons.shield_outlined;
      title = _hasAlert ? 'Есть тревога!' : 'Всё в норме';
      subtitle = widget.mode == _SensorsCardMode.admin
          ? (_hasAlert
              ? 'Откройте события и подтвердите статус'
              : 'Все датчики ЖК в норме')
          : (_hasAlert
              ? 'Подтверждённое событие в вашем подъезде'
              : 'Датчики вашего подъезда работают штатно');
    }

    final canTap = _interactive &&
        !_loading &&
        !(widget.mode == _SensorsCardMode.resident && _entrance == null);

    final card = Card(
      child: Opacity(
        opacity: disabled ? 0.65 : 1.0,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: canTap ? _open : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Датчики',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(width: 8),
                          if (_loading)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: color, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (widget.mode == _SensorsCardMode.admin &&
                          !_loading &&
                          _offlineCount > 0) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Не на связи: $_offlineCount из '
                            '${kEntrancesCount * kFloorsPerEntrance * 2}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(canTap ? Icons.chevron_right : Icons.lock_outline,
                    color: canTap ? null : Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );

    return PulsingAlert(active: canTap && _hasAlert, child: card);
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionCard({
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.bottomRight,
                child: Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }
}