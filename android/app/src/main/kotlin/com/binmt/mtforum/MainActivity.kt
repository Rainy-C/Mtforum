package com.binmt.mtforum

import android.Manifest
import android.app.DownloadManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val updateChannelName = "mtforum/update"
    private val notificationChannelName = "mtforum/notifications"
    private val privateMessageChannelId = "mtforum_private_messages"
    private val privateMessageNotificationId = 2001
    private val notificationPrefsName = "mtforum_system_notifications"
    private val unreadTouidsKey = "pm_unread_touids"
    private val notificationPermissionRequestedKey = "notification_permission_requested"
    private val notificationPermissionRequestCode = 4102
    private val peakRefreshRateSetting = "peak_refresh_rate"
    private val minimumValidRefreshRate = 30f
    private val refreshRateTolerance = 0.5f

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyAdaptiveRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        // 用户在系统设置中修改刷新率后，回到前台时重新跟随当前上限。
        applyAdaptiveRefreshRate()
    }

    private fun applyAdaptiveRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val targetMode = findBestDisplayMode() ?: return
            val attributes = window.attributes
            attributes.preferredDisplayModeId = targetMode.modeId
            attributes.preferredRefreshRate = targetMode.refreshRate
            window.attributes = attributes
            return
        }

        @Suppress("DEPRECATION")
        val display = windowManager.defaultDisplay
        @Suppress("DEPRECATION")
        val rates = display.supportedRefreshRates
        val hardwareMax = rates.maxOrNull() ?: display.refreshRate
        val cap = resolveRefreshRateCap(hardwareMax)
        val target = rates
            .filter { it <= cap + refreshRateTolerance }
            .maxOrNull()
            ?: display.refreshRate

        val attributes = window.attributes
        attributes.preferredRefreshRate = target
        window.attributes = attributes
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.M)
    private fun findBestDisplayMode(): android.view.Display.Mode? {
        val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        } ?: return null

        val currentMode = currentDisplay.mode
        val sameResolutionModes = currentDisplay.supportedModes.filter { mode ->
            mode.physicalWidth == currentMode.physicalWidth &&
                mode.physicalHeight == currentMode.physicalHeight
        }
        if (sameResolutionModes.isEmpty()) return currentMode

        val hardwareMax = sameResolutionModes.maxOf { it.refreshRate }
        val cap = resolveRefreshRateCap(hardwareMax)

        return sameResolutionModes
            .filter { it.refreshRate <= cap + refreshRateTolerance }
            .maxByOrNull { it.refreshRate }
            ?: sameResolutionModes.minByOrNull {
                kotlin.math.abs(it.refreshRate - cap)
            }
            ?: currentMode
    }

    private fun resolveRefreshRateCap(hardwareMax: Float): Float {
        val userPeak = runCatching {
            Settings.System.getFloat(contentResolver, peakRefreshRateSetting)
        }.getOrNull()

        // peak_refresh_rate 是 Android 常用的“用户允许的最高刷新率”设置。
        // OEM 未暴露该值时默认使用当前分辨率下设备支持的最高刷新率。
        return if (userPeak != null && userPeak >= minimumValidRefreshRate) {
            kotlin.math.min(userPeak, hardwareMax)
        } else {
            hardwareMax
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            updateChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getVersionInfo" -> result.success(getVersionInfo())
                "startDownload" -> {
                    val url = call.argument<String>("url")
                    val fileName = call.argument<String>("fileName")
                    if (url.isNullOrBlank() || fileName.isNullOrBlank()) {
                        result.error("ARGUMENT", "url/fileName 不能为空", null)
                    } else {
                        try {
                            result.success(startDownload(url, fileName))
                        } catch (e: Exception) {
                            result.error("DOWNLOAD", e.message, null)
                        }
                    }
                }
                "queryDownload" -> {
                    val id = call.argument<Number>("id")?.toLong()
                    if (id == null) {
                        result.error("ARGUMENT", "id 不能为空", null)
                    } else {
                        result.success(queryDownload(id))
                    }
                }
                "installDownload" -> {
                    val id = call.argument<Number>("id")?.toLong()
                    if (id == null) {
                        result.error("ARGUMENT", "id 不能为空", null)
                    } else {
                        result.success(installDownload(id))
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "syncPrivateMessages" -> {
                    try {
                        val rawMessages = call.argument<List<Map<String, Any?>>>("messages")
                            ?: emptyList()
                        syncPrivateMessageNotifications(rawMessages)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("NOTIFICATION", e.message, null)
                    }
                }
                "clearPrivateMessages" -> {
                    try {
                        clearPrivateMessageNotifications()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("NOTIFICATION", e.message, null)
                    }
                }
                "takePendingPrivateMessageTouid" -> {
                    val touid = intent?.getStringExtra("mtforum_pm_touid")
                    intent?.removeExtra("mtforum_pm_touid")
                    result.success(touid)
                }
                else -> result.notImplemented()
            }
        }
    }


    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun getVersionInfo(): Map<String, Any> {
        val info = packageManager.getPackageInfo(packageName, 0)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }

        return mapOf(
            "versionName" to (info.versionName ?: ""),
            "versionCode" to versionCode
        )
    }

    private fun ensurePrivateMessageNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            privateMessageChannelId,
            "私信消息",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "MT论坛私信未读提醒"
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }

    private fun canPostNotifications(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotificationPermissionOnce() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || canPostNotifications()) {
            return
        }

        val prefs = getSharedPreferences(notificationPrefsName, Context.MODE_PRIVATE)
        if (prefs.getBoolean(notificationPermissionRequestedKey, false)) return

        prefs.edit().putBoolean(notificationPermissionRequestedKey, true).apply()
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode
        )
    }

    private fun syncPrivateMessageNotifications(messages: List<Map<String, Any?>>) {
        ensurePrivateMessageNotificationChannel()
        requestNotificationPermissionOnce()
        if (!canPostNotifications()) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val prefs = getSharedPreferences(notificationPrefsName, Context.MODE_PRIVATE)
        val previousTouids = prefs.getStringSet(unreadTouidsKey, emptySet())?.toSet()
            ?: emptySet()
        val currentTouids = linkedSetOf<String>()
        val editor = prefs.edit()

        for (item in messages) {
            val touid = item["touid"]?.toString()?.trim().orEmpty()
            if (touid.isEmpty()) continue

            val username = item["username"]?.toString()?.trim().orEmpty()
            val message = item["message"]?.toString()?.trim().orEmpty()
            currentTouids.add(touid)

            val fingerprintKey = "pm_fingerprint_$touid"
            // lastTime 是“1分钟前/2分钟前”这种相对时间，会自行变化，不能参与
            // 去重指纹，否则同一条消息会每隔一分钟被误判成新消息。
            val fingerprint = message
            val previousFingerprint = prefs.getString(fingerprintKey, null)
            val sameMessage = previousFingerprint == fingerprint
            val wasAlreadyUnread = previousTouids.contains(touid)

            val launchIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("mtforum_pm_touid", touid)
            }
            val pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
            val contentIntent = PendingIntent.getActivity(
                this,
                touid.hashCode() and 0x7fffffff,
                launchIntent,
                pendingIntentFlags
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, privateMessageChannelId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

            // 已经提醒过且内容未变化时不重新 post。这样用户手动划掉通知后，
            // 不会在下一轮 30 秒轮询里被同一条未读消息再次顶回来。
            if (!wasAlreadyUnread || !sameMessage) {
                val body = message.ifEmpty { "收到一条新私信" }
                builder
                    .setSmallIcon(R.drawable.ic_launcher_monochrome)
                    .setContentTitle(username.ifEmpty { "MT论坛私信" })
                    .setContentText(body)
                    .setStyle(Notification.BigTextStyle().bigText(body))
                    .setCategory(Notification.CATEGORY_MESSAGE)
                    .setVisibility(Notification.VISIBILITY_PRIVATE)
                    .setAutoCancel(true)
                    .setContentIntent(contentIntent)

                manager.notify(
                    "mtforum_pm_$touid",
                    privateMessageNotificationId,
                    builder.build()
                )
            }
            editor.putString(fingerprintKey, fingerprint)
        }

        for (touid in previousTouids - currentTouids) {
            manager.cancel("mtforum_pm_$touid", privateMessageNotificationId)
            editor.remove("pm_fingerprint_$touid")
        }

        editor.putStringSet(unreadTouidsKey, currentTouids).apply()
    }

    private fun clearPrivateMessageNotifications() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val prefs = getSharedPreferences(notificationPrefsName, Context.MODE_PRIVATE)
        val previousTouids = prefs.getStringSet(unreadTouidsKey, emptySet())?.toSet()
            ?: emptySet()
        val editor = prefs.edit()

        for (touid in previousTouids) {
            manager.cancel("mtforum_pm_$touid", privateMessageNotificationId)
            editor.remove("pm_fingerprint_$touid")
        }
        editor.remove(unreadTouidsKey).apply()
    }

    private fun startDownload(url: String, fileName: String): Long {
        val parsedUrl = Uri.parse(url)
        if (parsedUrl.scheme != "http" && parsedUrl.scheme != "https") {
            throw IllegalArgumentException("软件更新下载地址仅支持 http/https：${parsedUrl.scheme ?: "无协议"}")
        }
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val request = DownloadManager.Request(parsedUrl)
            .setTitle("MT论坛更新")
            .setDescription(fileName)
            .setMimeType("application/vnd.android.package-archive")
            .setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
            )
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true)
            .setDestinationInExternalFilesDir(
                this,
                Environment.DIRECTORY_DOWNLOADS,
                fileName
            )

        return manager.enqueue(request)
    }

    private fun queryDownload(id: Long): Map<String, Any> {
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val query = DownloadManager.Query().setFilterById(id)
        manager.query(query).use { cursor ->
            if (!cursor.moveToFirst()) {
                return mapOf(
                    "status" to DownloadManager.STATUS_FAILED,
                    "downloaded" to 0L,
                    "total" to 0L
                )
            }

            val status = cursor.getInt(
                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
            )
            val downloaded = cursor.getLong(
                cursor.getColumnIndexOrThrow(
                    DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR
                )
            )
            val total = cursor.getLong(
                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            )

            return mapOf(
                "status" to status,
                "downloaded" to downloaded,
                "total" to total
            )
        }
    }

    private fun installDownload(id: Long): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(settingsIntent)
            return "permission"
        }

        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val uri = manager.getUriForDownloadedFile(id) ?: return "failed"

        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        startActivity(installIntent)
        return "started"
    }
}
