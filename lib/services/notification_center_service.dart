import '../models/notification_item.dart';
import 'api_client.dart';

class NotificationCenterService {
  final ApiClient _api;
  NotificationCenterService(this._api);

  Future<List<NotificationItem>> getNotifications() async {
    final res = await _api.get('/notifications');
    return (res.data as List)
        .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> getUnreadCount() async {
    final res = await _api.get('/notifications/unread-count');
    return (res.data as Map<String, dynamic>)['count'] as int;
  }

  Future<void> markRead(String id) => _api.put('/notifications/$id/read');

  Future<void> markAllRead() => _api.put('/notifications/read-all');
}
