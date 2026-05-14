package kz.smartresidency.app

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlin.math.absoluteValue

class SmartResidencyMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val kind = data["kind"].orEmpty()
        val foreground = isAppForeground()
        Log.d(TAG, "FCM received kind=$kind foreground=$foreground")

        if (!foreground || !isNativeForegroundKind(kind)) {
            return
        }

        ensureChannels()
        showForegroundNotification(kind, data, message.notification)
    }

    private fun showForegroundNotification(
        kind: String,
        data: Map<String, String>,
        remoteNotification: RemoteMessage.Notification?
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.d(TAG, "POST_NOTIFICATIONS is not granted")
            return
        }

        val title = data["title"]
            ?: remoteNotification?.title
            ?: fallbackTitle(kind)
        val body = data["body"]
            ?: remoteNotification?.body
            ?: fallbackBody(kind, data)
        val notificationId = notificationIdFor(kind, data)
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)

        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, channelIdFor(kind))
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        NotificationManagerCompat.from(this).notify(notificationId, notification)
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                BARRIER_CHANNEL_ID,
                "Шлагбаум",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Уведомления о неизвестных номерах"
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(
                PARKING_CHANNEL_ID,
                "Парковка",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Уведомления о парковочных местах"
            }
        )
    }

    private fun isAppForeground(): Boolean {
        val state = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(state)
        return state.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND ||
            state.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE
    }

    private fun isNativeForegroundKind(kind: String): Boolean {
        return kind == "unknown_vehicle" ||
            kind == "guest_arrived" ||
            kind == "parking_alert" ||
            kind == "parking_spot_freed"
    }

    private fun channelIdFor(kind: String): String {
        return when (kind) {
            "unknown_vehicle", "guest_arrived" -> BARRIER_CHANNEL_ID
            "parking_alert", "parking_spot_freed" -> PARKING_CHANNEL_ID
            else -> PARKING_CHANNEL_ID
        }
    }

    private fun notificationIdFor(kind: String, data: Map<String, String>): Int {
        val stable = data["event_id"] ?: data["spot_id"] ?: data["spot_number"] ?: data["guest_name"] ?: kind
        return stable.hashCode().absoluteValue
    }

    private fun fallbackTitle(kind: String): String {
        return when (kind) {
            "unknown_vehicle" -> "Неизвестный автомобиль"
            "guest_arrived" -> "Ваш гость въехал"
            "parking_alert" -> "Ваше место занято"
            "parking_spot_freed" -> "Ваше место освобождено"
            else -> "Smart Residency"
        }
    }

    private fun fallbackBody(kind: String, data: Map<String, String>): String {
        val spot = data["spot_number"].orEmpty()
        val plate = data["plate_number"].orEmpty()
        val guest = data["guest_name"].orEmpty()
        return when (kind) {
            "unknown_vehicle" -> if (plate.isNotEmpty()) "Номер: $plate требует решения" else "Требуется решение"
            "guest_arrived" -> if (guest.isNotEmpty()) "Гость $guest прибыл на территорию ЖК" else "Гость прибыл на территорию ЖК"
            "parking_alert" -> if (spot.isNotEmpty()) "Место $spot занято посторонним ТС" else "Постоянное место занято"
            "parking_spot_freed" -> if (spot.isNotEmpty()) "Место $spot снова свободно" else "Постоянное место снова свободно"
            else -> "Новое уведомление"
        }
    }

    companion object {
        private const val TAG = "SmartResidencyFCM"
        private const val BARRIER_CHANNEL_ID = "barrier_events_v2"
        private const val PARKING_CHANNEL_ID = "parking_events_v2"
    }
}
