import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'login_page.dart';
import 'ownership_verification_page.dart';
import 'register_flow_page.dart';
import 'vehicles_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ApiClient _api = ApiClient.instance;
  final AuthService _auth = AuthService();
  Future<Map<String, dynamic>?>? _profileFuture;

  @override
  void initState() {
    super.initState();
    _reloadProfile();
  }

  void _reloadProfile() {
    setState(() {
      _profileFuture = _fetchProfile();
    });
  }

  Future<Map<String, dynamic>?> _fetchProfile() async {
    try {
      final res = await _api.get('/auth/me');
      return Map<String, dynamic>.from(res.data as Map);
    } catch (_) {
      return null;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Администратор';
      case 'resident':
        return 'Житель';
      case 'owner':
        return 'Владелец';
      case 'tenant':
        return 'Арендатор';
      default:
        return role.isNotEmpty ? role : 'Не указано';
    }
  }

  String _verificationLabel(String status) {
    switch (status) {
      case 'pending':
        return 'На проверке';
      case 'approved':
        return 'Подтверждено';
      case 'rejected':
        return 'Отклонено';
      default:
        return 'Не отправлено';
    }
  }

  String _roleDescription(String role, String verificationStatus) {
    if (role == 'admin') {
      return 'Вы вошли как администратор. Вам доступны просмотр заявок, смена их статусов и дальнейшее управление сервисной частью приложения.';
    }
    if (verificationStatus == 'approved') return 'Ваш статус подтверждён. Основной функционал доступен.';
    if (verificationStatus == 'pending') return 'Ваши документы отправлены и сейчас находятся на проверке.';
    if (verificationStatus == 'rejected') return 'Проверка была отклонена. Вы можете отправить документы повторно.';
    return 'Вы ещё не отправляли документы на подтверждение статуса.';
  }

  Color _verificationColor(BuildContext context, String status) {
    switch (status) {
      case 'approved': return Colors.green;
      case 'pending': return Colors.orange;
      case 'rejected': return Colors.red;
      default: return Theme.of(context).colorScheme.outline;
    }
  }

  IconData _verificationIcon(String status) {
    switch (status) {
      case 'approved': return Icons.verified;
      case 'pending': return Icons.hourglass_top_rounded;
      case 'rejected': return Icons.cancel_outlined;
      default: return Icons.help_outline;
    }
  }

  Future<void> _openVerificationPage() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const OwnershipVerificationPage()));
    if (!mounted) return;
    _reloadProfile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: SafeArea(
        child: StreamBuilder<AppUser?>(
          stream: _auth.authStateChanges,
          builder: (context, authSnapshot) {
            final user = authSnapshot.data;

            if (user == null) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Профиль', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const CircleAvatar(radius: 34, child: Icon(Icons.person, size: 34)),
                          const SizedBox(height: 12),
                          Text('Вы не вошли', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          const Text('Войдите или зарегистрируйтесь, чтобы пользоваться профилем', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage())),
                              child: const Text('Войти'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterFlowPage())),
                              child: const Text('Регистрация'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return FutureBuilder<Map<String, dynamic>?>(
              future: _profileFuture,
              builder: (context, profileSnapshot) {
                if (profileSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = profileSnapshot.data ?? <String, dynamic>{};
                final rawRole = (data['role'] ?? '').toString();
                final role = rawRole.isNotEmpty ? rawRole : (_api.userRole ?? 'resident');
                final verificationStatus = (data['verification_status'] ?? 'not_submitted').toString();
                final fullName = (data['full_name'] ?? user.email).toString();
                final phone = (data['phone'] ?? '').toString();
                final iin = (data['iin'] ?? '').toString();
                final address = (data['full_address'] ?? '').toString();
                final verificationColor = _verificationColor(context, verificationStatus);

                return RefreshIndicator(
                  onRefresh: () async { _reloadProfile(); await _profileFuture; },
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Профиль', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const CircleAvatar(radius: 34, child: Icon(Icons.person, size: 34)),
                              const SizedBox(height: 12),
                              Text(fullName, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
                              const SizedBox(height: 6),
                              Text(user.email),
                              if (phone.isNotEmpty) ...[const SizedBox(height: 6), Text(phone)],
                              if (iin.isNotEmpty) ...[const SizedBox(height: 6), Text('ИИН: $iin')],
                              if (address.isNotEmpty) ...[const SizedBox(height: 6), Text(address, textAlign: TextAlign.center)],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.verified_user_outlined),
                              title: const Text('Роль'),
                              subtitle: Text(_roleLabel(role)),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: Icon(_verificationIcon(verificationStatus)),
                              title: const Text('Статус проверки'),
                              subtitle: Text(_verificationLabel(verificationStatus)),
                              trailing: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(color: verificationColor, shape: BoxShape.circle),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (role != 'admin' && verificationStatus != 'approved')
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _openVerificationPage,
                            child: Text(
                              verificationStatus == 'rejected' ? 'Отправить повторно'
                                  : verificationStatus == 'pending' ? 'Открыть проверку'
                                  : 'Подтвердить статус',
                            ),
                          ),
                        ),
                      if (role == 'admin') ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Icon(Icons.admin_panel_settings_outlined),
                                const SizedBox(width: 12),
                                Expanded(child: Text('Вы вошли под ролью администратора.', style: Theme.of(context).textTheme.bodyMedium)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_roleDescription(role, verificationStatus)))),
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.directions_car),
                          title: const Text('Мои автомобили'),
                          subtitle: const Text('Управление зарегистрированными авто'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VehiclesPage())),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonal(
                          onPressed: () async {
                            await _auth.signOut();
                            if (!mounted) return;
                            _reloadProfile();
                          },
                          child: const Text('Выйти'),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
