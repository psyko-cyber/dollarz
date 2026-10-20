package it.dollarz.app

import android.app.Notification
import android.content.Context
import android.provider.Telephony
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Copia in un file privato dell'app le notifiche delle app delle banche e gli SMS
 * delle banche mostrati dall'app dei messaggi: Dollarz lo legge all'apertura
 * (o subito, se è aperto) e ne fa movimenti.
 * Le notifiche delle altre app e gli SMS degli altri mittenti non vengono salvati.
 */
class BankNotificationListener : NotificationListenerService() {
    companion object {
        private const val FILE = "bank_notifs.jsonl"
        private const val PREFS = "dollarz_bank"
        private val DEFAULT_KEYS = listOf("revolut", "fineco", "traderepublic")

        /** Mittenti degli SMS delle banche: inizio del nome, minuscolo e senza spazi. */
        private val SMS_SENDERS = listOf("fineco", "revolut", "traderepub")
        private val SMS_APPS = setOf(
            "com.google.android.apps.messaging", "com.samsung.android.messaging", "com.android.mms",
            "com.android.messaging", "com.oneplus.mms", "com.motorola.messaging",
        )

        /** Notifiche più vecchie (ancora visibili quando il listener si collega) non si leggono. */
        private const val MAX_AGE = 3L * 24 * 3600 * 1000
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

        fun isSmsApp(ctx: Context, pkg: String): Boolean {
            if (pkg in SMS_APPS) return true
            return try {
                pkg == Telephony.Sms.getDefaultSmsPackage(ctx)
            } catch (e: Exception) {
                false
            }
        }

        private fun isBankSender(name: CharSequence?): Boolean {
            val n = name?.toString()?.lowercase()?.filter { it.isLetterOrDigit() } ?: return false
            return SMS_SENDERS.any { n.startsWith(it) }
        }

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
        handle(sbn)
    }

    /** Al collegamento (telefono riavviato, app aggiornata) legge anche quelle ancora visibili. */
    override fun onListenerConnected() {
        try {
            activeNotifications?.forEach { handle(it) }
        } catch (e: Exception) {
        }
    }

    private fun handle(sbn: StatusBarNotification) {
        val pkg = sbn.packageName ?: return
        if (pkg == packageName) return
        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (n.flags and Notification.FLAG_ONGOING_EVENT != 0) return
        val recs = when {
            isBank(this, pkg) -> listOfNotNull(appRecord(sbn, n))
            isSmsApp(this, pkg) -> smsRecords(sbn, n)
            else -> return
        }
        val old = System.currentTimeMillis() - MAX_AGE
        val fresh = recs.filter { it.getLong("at") >= old }
        if (fresh.isEmpty()) return
        synchronized(lock) {
            val f = File(filesDir, FILE)
            // se l'app non viene aperta per molto tempo, non cresce all'infinito
            if (f.exists() && f.length() > 2_000_000) return
            f.appendText(fresh.joinToString("") { it.toString() + "\n" })
        }
        try {
            onNew?.invoke()
        } catch (e: Exception) {
        }
    }

    private fun appRecord(sbn: StatusBarNotification, n: Notification): JSONObject? {
        val ex = n.extras
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = ex.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val big = ex.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val sub = ex.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
        if (title.isBlank() && text.isBlank() && big.isBlank()) return null
        return record(sbn.packageName, title, text, big, sub, sbn.postTime, sbn.key)
    }

    /** SMS: solo i messaggi dei mittenti delle banche, uno per messaggio, con l'ora del messaggio. */
    private fun smsRecords(sbn: StatusBarNotification, n: Notification): List<JSONObject> {
        val ex = n.extras
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val style = try {
            NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(n)
        } catch (e: Exception) {
            null
        }
        val msgs = style?.messages.orEmpty()
        if (msgs.isEmpty()) {
            if (!isBankSender(title)) return emptyList()
            val text = (ex.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: ex.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: ""
            if (text.isBlank()) return emptyList()
            return listOf(record(sbn.packageName, title, text, "", "", sbn.postTime, sbn.key))
        }
        return msgs.mapNotNull { m ->
            val sender = m.person?.name?.toString() ?: title
            val text = m.text?.toString() ?: ""
            if (!isBankSender(sender) || text.isBlank()) return@mapNotNull null
            record(sbn.packageName, sender, text, "", "", if (m.timestamp > 0) m.timestamp else sbn.postTime, sbn.key)
        }
    }

    private fun record(pkg: String, title: String, text: String, big: String, sub: String, at: Long, key: String?) =
        JSONObject()
            .put("pkg", pkg)
            .put("title", title)
            .put("text", text)
            .put("big", big)
            .put("sub", sub)
            .put("at", at)
            .put("key", key ?: "")
}
