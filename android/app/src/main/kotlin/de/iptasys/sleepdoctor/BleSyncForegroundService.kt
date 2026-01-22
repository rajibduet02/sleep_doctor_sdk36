package de.iptasys.sleepdoctor

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Foreground service to keep BLE sync alive during long operations
 * Required for Android 12+ background execution compliance
 */
class BleSyncForegroundService : Service() {
    
    companion object {
        private const val CHANNEL_ID = "ble_sync_foreground_service_channel"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_NAME = "BLE Sync Service"
        
        private var isRunning = false
        
        fun isServiceRunning(): Boolean = isRunning
    }
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "START_FOREGROUND" -> {
                startForeground(NOTIFICATION_ID, createNotification())
                isRunning = true
            }
            "STOP_FOREGROUND" -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                isRunning = false
            }
        }
        return START_NOT_STICKY // Don't restart if killed
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        return null // Bound service not needed
    }
    
    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW // Low priority - don't disturb user
            ).apply {
                description = "Keeps BLE sync active during data transfer"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val notificationIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        
        // Use app launcher icon or fallback to system icon
        val iconResId = resources.getIdentifier("ic_launcher", "mipmap", packageName)
        val smallIcon = if (iconResId != 0) iconResId else android.R.drawable.ic_dialog_info
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SleepDoctor Sync")
            .setContentText("Synchronizing sleep data...")
            .setSmallIcon(smallIcon)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }
}
