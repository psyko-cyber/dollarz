package it.dollarz.app

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Copia le notifiche delle app delle banche in un file privato dell'app:
 * Dollarz lo legge all'apertura (o subito, se è aperto) e ne fa movimenti.
 * Le notifiche delle altre app non vengono nemmeno lette.
 */
class BankNotificationListener : NotificationListenerService() {
    companion object {
        private const val FILE = "bank_notifs.jsonl"
        private const val PREFS = "dollarz_bank"
        private val DEFAULT_KEYS = listOf("revolut", "fineco", "traderepublic")
        private val lock = Any()

        /** Avvisa l'app aperta che è arrivata una notifica nuova. */
        @Volatile
        var onNew: (() -> Unit)? = null

        fun setApps(ctx: Context, apps: List<String>) {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putStringSet("apps", apps.toSet()).apply()
        }

        private fun apps(ctx: Context): Set<String> =
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet("apps", null) ?: emptySet()

        fun isBank(ctx: Context, pkg: String): Boolean =
            pkg in apps(ctx) || DEFAULT_KEYS.any { pkg.lowercase().contains(it) }

        /** Restituisce le notifiche in attesa (JSON) e le cancella. */
        fun take(ctx: Context): String {
            synchronized(lock) {
                val f = File(ctx.filesDir, FILE)
                if (!f.exists()) return "[]"
                val out = JSONArray()
                f.readLines().forEach { line ->
                    try {
                        if (line.isNotBlank()) out.put(JSONObject(line))
                    } catch (e: Exception) {
                    }
                }
                f.delete()
                return out.toString()
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val pkg = sbn.packageName ?: return
        if (pkg == packageName || !isBank(this, pkg)) return
        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (n.flags and Notification.FLAG_ONGOING_EVENT != 0) return
        val ex = n.extras
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = ex.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val big = ex.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val sub = ex.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
        if (title.isBlank() && text.isBlank() && big.isBlank()) return
        val o = JSONObject()
            .put("pkg", pkg)
            .put("title", title)
            .put("text", text)
            .put("big", big)
            .put("sub", sub)
            .put("at", sbn.postTime)
            .put("key", sbn.key ?: "")
        synchronized(lock) {
            val f = File(filesDir, FILE)
            // se l'app non viene aperta per molto tempo, non cresce all'infinito
            if (f.exists() && f.length() > 2_000_000) return
            f.appendText(o.toString() + "\n")
        }
        try {
            onNew?.invoke()
        } catch (e: Exception) {
        }
    }
}
