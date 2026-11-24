package com.odakkilidi.app

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import java.time.LocalDate

/**
 * Ayarların saklandığı yer.
 *  - "active": şu an geçerli kurallar
 *  - "pending" + "pendingDate": gevşeten bir değişiklik; o tarihte (ertesi gün) geçerli olur
 *  - "sessions": ders oturumları (başlangıç, bitiş, hedefler)
 *  - "unlockDate": kaldırma izni günü; sadece o gün koruma kapalıdır
 */
object Store {
    private fun p(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences("odak", Context.MODE_PRIVATE)

    fun today(): String = LocalDate.now().toString()
    fun tomorrow(): String = LocalDate.now().plusDays(1).toString()

    private fun promote(ctx: Context) {
        val sp = p(ctx)
        val date = sp.getString("pendingDate", null) ?: return
        if (date <= today()) {
            val pend = sp.getString("pending", null)
            val e = sp.edit()
            if (pend != null) e.putString("active", pend)
            e.remove("pending").remove("pendingDate").apply()
        }
    }

    fun active(ctx: Context): Config {
        promote(ctx)
        return Rules.fromJson(p(ctx).getString("active", null)) ?: Config(emptyList())
    }

    fun hasSavedOnce(ctx: Context): Boolean = p(ctx).contains("active")

    /** Bekleyen (yarın geçerli olacak) ayar ve tarihi. */
    fun pending(ctx: Context): Pair<Config, String>? {
        promote(ctx)
        val sp = p(ctx)
        val c = Rules.fromJson(sp.getString("pending", null)) ?: return null
        val d = sp.getString("pendingDate", null) ?: return null
        return Pair(c, d)
    }

    /** Düzenleme ekranlarında gösterilecek ayar: varsa bekleyen, yoksa aktif. */
    fun editable(ctx: Context): Config = pending(ctx)?.first ?: active(ctx)

    /** Kaydet. true = hemen uygulandı, false = yarın geçerli olacak. */
    fun save(ctx: Context, c: Config): Boolean {
        val cur = active(ctx)
        val sp = p(ctx)
        val first = !hasSavedOnce(ctx) || cur.rules.isEmpty()
        return if (first || Rules.isStricterOrEqual(c, cur)) {
            sp.edit().putString("active", Rules.toJson(c)).remove("pending").remove("pendingDate").apply()
            true
        } else {
            sp.edit().putString("pending", Rules.toJson(c)).putString("pendingDate", tomorrow()).apply()
            false
        }
    }

    fun cancelPending(ctx: Context) {
        p(ctx).edit().remove("pending").remove("pendingDate").apply()
    }

    // ---- Ders modu ----
    /** Bitmemiş (şu an süren ya da ileride başlayacak) oturumlar, başlangıca göre sıralı. */
    fun sessions(ctx: Context): List<Session> {
        val now = System.currentTimeMillis()
        val all = Rules.sessionsFromJson(p(ctx).getString("sessions", null))
        val alive = all.filter { it.end > now }.sortedBy { it.start }
        if (alive.size != all.size) p(ctx).edit().putString("sessions", Rules.sessionsToJson(alive)).apply()
        return alive
    }

    fun activeSessions(ctx: Context): List<Session> {
        val now = System.currentTimeMillis()
        return sessions(ctx).filter { it.start <= now }
    }

    /** Yeni ders oturumu ekle. Erken bitirilemez, iptal edilemez. */
    fun addSession(ctx: Context, s: Session) {
        val list = sessions(ctx) + s
        p(ctx).edit()
            .putString("sessions", Rules.sessionsToJson(list))
            .putString("lastSession", Rules.sessionsToJson(listOf(s)))
            .apply()
    }

    /** Son ders oturumunda seçilen hedefler (ekranı doldurmak için). */
    fun lastSessionTargets(ctx: Context): Pair<Set<String>, Set<String>>? {
        val s = Rules.sessionsFromJson(p(ctx).getString("lastSession", null)).firstOrNull() ?: return null
        return s.apps to s.sites
    }

    fun blockState(ctx: Context): BlockState =
        Rules.blockState(active(ctx), Rules.weekMinuteNow(), activeSessions(ctx))

    // ---- Kaldırma izni ----
    fun unlockDate(ctx: Context): String? {
        val d = p(ctx).getString("unlockDate", null) ?: return null
        if (d < today()) {
            p(ctx).edit().remove("unlockDate").apply()
            return null
        }
        return d
    }

    fun unlockedToday(ctx: Context): Boolean = unlockDate(ctx) == today()

    fun requestUnlock(ctx: Context) {
        p(ctx).edit().putString("unlockDate", tomorrow()).apply()
    }

    fun cancelUnlock(ctx: Context) {
        p(ctx).edit().remove("unlockDate").apply()
    }

    // ---- Cihaz yöneticisi ----
    fun adminComponent(ctx: Context) = ComponentName(ctx, AdminReceiver::class.java)

    fun isAdminActive(ctx: Context): Boolean {
        val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        return dpm.isAdminActive(adminComponent(ctx))
    }

    /** Ayarlar ekranlarında uygulamayı kapatma/silme koruması açık mı? */
    fun guardActive(ctx: Context): Boolean = isAdminActive(ctx) && !unlockedToday(ctx)
}
