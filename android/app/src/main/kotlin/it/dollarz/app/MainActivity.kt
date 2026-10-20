package it.dollarz.app

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FragmentActivity: serve a local_auth per la richiesta dell'impronta
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null
    private var pendingShared: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // dati finanziari: niente anteprima nelle app recenti e niente screenshot
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        if (savedInstanceState == null) handleShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShare(intent)
        pendingShared?.let {
            pendingShared = null
            channel?.invokeMethod("sharedFile", it)
        }
    }

    override fun onDestroy() {
        BankNotificationListener.onNew = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // aggiornamento dentro l'app: apre l'installer di Android sull'APK scaricato
        MethodChannel(messenger, "dollarz/update").setMethodCallHandler { call, result ->
            if (call.method != "installApk") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val uri = FileProvider.getUriForFile(this, "$packageName.updates", File(call.arguments as String))
                startActivity(
                    Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, "application/vnd.android.package-archive")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(true)
            } catch (e: Exception) {
                result.error("install", e.message, null)
            }
        }

        val ch = MethodChannel(messenger, "dollarz/native")
        channel = ch
        // il listener gira su un altro thread: il canale va usato da quello principale
        BankNotificationListener.onNew = { runOnUiThread { ch.invokeMethod("bankNotif", null) } }
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "takeSharedFile" -> {
                        result.success(pendingShared)
                        pendingShared = null
                    }
                    "notifAccess" -> result.success(NotificationManagerCompat.getEnabledListenerPackages(this).contains(packageName))
                    "openNotifSettings" -> {
                        openNotifSettings()
                        result.success(true)
                    }
                    "openAppDetails" -> {
                        startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    }
                    "takeBankNotifs" -> result.success(BankNotificationListener.take(this))
                    "setBankApps" -> {
                        @Suppress("UNCHECKED_CAST")
                        BankNotificationListener.setApps(this, (call.arguments as? List<String>) ?: emptyList())
                        result.success(true)
                    }
                    "setSecure" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("native", e.message, null)
            }
        }
    }

    private fun openNotifSettings() {
        val me = ComponentName(this, BankNotificationListener::class.java)
        val detail = if (Build.VERSION.SDK_INT >= 30) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, me.flattenToString())
        } else {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        }
        try {
            startActivity(detail.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    /** Condividi → Dollarz: copia il file ricevuto nella cache privata e ne tiene il percorso. */
    private fun handleShare(intent: Intent?) {
        if (intent == null) return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            Intent.ACTION_VIEW -> intent.data
            else -> null
        }
        val dir = File(cacheDir, "shared")
        try {
            if (uri == null) {
                // qualche app condivide l'estratto come testo
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (intent.action == Intent.ACTION_SEND && text != null && text.length > 20) {
                    dir.mkdirs()
                    dir.listFiles()?.forEach { it.delete() }
                    val out = File(dir, "condiviso.csv")
                    out.writeText(text)
                    pendingShared = out.absolutePath
                }
                return
            }
            dir.mkdirs()
            dir.listFiles()?.forEach { it.delete() }
            val name = (queryName(uri) ?: "estratto").replace(Regex("[^A-Za-z0-9._-]"), "_").take(80)
            val out = File(dir, name)
            contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { output ->
                    val buf = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        total += n
                        if (total > 30L * 1024 * 1024) throw IllegalStateException("file troppo grande")
                        output.write(buf, 0, n)
                    }
                }
            }
            pendingShared = out.absolutePath
        } catch (e: Exception) {
            pendingShared = null
        }
    }

    private fun queryName(uri: Uri): String? = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    } catch (e: Exception) {
        null
    }
}
