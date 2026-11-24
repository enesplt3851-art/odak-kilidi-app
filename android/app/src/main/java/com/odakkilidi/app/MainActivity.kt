package com.odakkilidi.app

import android.app.Activity
import android.app.AlertDialog
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class MainActivity : Activity() {

    private lateinit var root: LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        root = Ui.page(this)
    }

    override fun onResume() {
        super.onResume()
        render()
    }

    private fun dp(v: Int) = Ui.dp(this, v)

    private fun render() {
        root.removeAllViews()
        val active = Store.active(this)
        val shown = Store.editable(this)
        val wm = Rules.weekMinuteNow()

        val days = listOf("Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar")
        root.addView(Ui.hero(this, "Odak Kilidi", "${days[wm / 1440]} · ${Rules.fmt(wm % 1440)} — odaklan, gerisi bekleyebilir"))

        // ---------- Şu anki durum ----------
        val running = Rules.activeRules(active, wm)
        val sessions = Store.sessions(this)
        val now = System.currentTimeMillis()
        val liveSessions = sessions.filter { it.start <= now }
        if (running.isEmpty() && liveSessions.isEmpty()) {
            val next = Rules.nextStart(active, wm)
            val txt = if (active.rules.isEmpty() && sessions.isEmpty()) "🔓 Şu an serbest"
            else "🔓 Şu an serbest" + (next?.let { "\nSıradaki: ${it.first.name} · ${Rules.fmtWeekMinute((wm + it.second) % WEEK, wm)}" } ?: "")
            root.addView(Ui.banner(this, txt, Ui.GREEN))
        } else {
            val lines = running.map { (r, left) -> "• ${r.name} — ${Rules.fmtWeekMinute((wm + left) % WEEK, wm)}'e kadar" } +
                liveSessions.map { "• 📚 Ders — ${Rules.fmtMillis(it.end)}'e kadar" }
            root.addView(Ui.banner(this, "🔒 Şu an kilitli\n" + lines.joinToString("\n"), Ui.RED))
        }

        // ---------- Ders modu ----------
        root.addView(Ui.header(this, "📚 Ders modu"))
        if (sessions.isEmpty()) {
            root.addView(Ui.note(this, "Ders çalışacağın zaman bas: süreyi, başlangıç saatini ve neyin kilitleneceğini seçersin. Başladıktan sonra erken bitirilemez."))
        }
        for (ss in sessions) {
            val live = ss.start <= now
            val leftMin = ((ss.end - now + 59_999) / 60_000).toInt()
            val head = if (live) "🔒 Ders sürüyor — ${Rules.fmtMillis(ss.end)}'e kadar (${Rules.fmtDuration(leftMin)} kaldı)"
                else "⏰ Planlandı — ${Rules.fmtMillis(ss.start)} → ${Rules.fmtMillis(ss.end)}"
            root.addView(Ui.card(this, "$head\nKilitli: ${targetsSummary(ss.targets())}", if (live) Ui.ACCENT else Ui.AMBER))
        }
        root.addView(Ui.button(this, "▶  Ders çalışmaya başla", primary = true) {
            startActivity(Intent(this, StudyActivity::class.java))
        })

        // ---------- Kurallar ----------
        root.addView(Ui.header(this, "🗂️ Kurallar"))
        if (shown.rules.isEmpty()) root.addView(Ui.note(this, "Henüz kural yok."))
        shown.rules.forEachIndexed { idx, r ->
            val isOn = running.any { it.first.id == r.id }
            val when_ = if (r.ranges.isEmpty()) "Saat yok — düzenleyip saat ekle"
                else Rules.fmtDays(r.days) + " · " + r.ranges.joinToString(", ") { Rules.fmtRange(it) }
            root.addView(Ui.ruleCard(this,
                badge = if (r.kind == KIND_DERS) "📚 DERS" else "📅 RUTİN",
                badgeColor = if (r.kind == KIND_DERS) Ui.ACCENT else Ui.ACCENT2,
                title = r.name,
                line1 = when_,
                line2 = targetsSummary(r.targets()),
                locked = isOn
            ) {
                startActivity(Intent(this, RuleEditActivity::class.java).putExtra("index", idx))
            })
        }
        root.addView(Ui.button(this, "+  Yeni kural ekle", primary = true) {
            startActivity(Intent(this, RuleEditActivity::class.java).putExtra("index", -1))
        })
        root.addView(Ui.note(this, "Kısıtlamayı ARTIRAN değişiklik hemen geçerli olur. AZALTAN değişiklik (saat kısaltma, hedef çıkarma, kural silme) ertesi gün geçerli olur."))

        // ---------- Bekleyen değişiklik ----------
        Store.pending(this)?.let { (_, date) ->
            root.addView(Ui.card(this, "⏳ Bekleyen değişiklikler\n$date tarihinde geçerli olacak. Yukarıdaki liste o hâli gösteriyor.", Ui.AMBER))
            root.addView(Ui.button(this, "Bekleyen değişiklikleri iptal et") {
                Store.cancelPending(this)
                render()
            })
        }

        // ---------- Kurulum ----------
        val adminOk = Store.isAdminActive(this)
        val accOk = isAccessibilityOn()
        if (!adminOk || !accOk) {
            root.addView(Ui.header(this, "⚠️ Kurulum tamamlanmadı"))
            if (!accOk) {
                root.addView(Ui.note(this, "1) Erişilebilirlik izni: Engellemeyi bu yapar. Ayarlar'da \"Odak Kilidi\"ni bul ve aç.\nAndroid 13+ ise önce: Ayarlar → Uygulamalar → Odak Kilidi → sağ üst ⋮ → \"Kısıtlanmış ayarlara izin ver\"."))
                root.addView(Ui.button(this, "Erişilebilirlik ayarlarını aç") {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                })
            }
            if (!adminOk) {
                root.addView(Ui.note(this, "2) Cihaz yöneticisi: Açıkken uygulama silinemez."))
                root.addView(Ui.button(this, "Cihaz yöneticisini etkinleştir") { askAdmin() })
            }
        }

        // ---------- Kaldırma ----------
        root.addView(Ui.header(this, "🗑️ Uygulamayı kaldırma"))
        val ud = Store.unlockDate(this)
        when {
            Store.unlockedToday(this) -> {
                root.addView(Ui.note(this, "Bugün kaldırma izni günü: koruma kapalı. Silmek için önce yöneticiliği kaldır, sonra uygulamayı normal şekilde sil."))
                if (adminOk) root.addView(Ui.button(this, "Yöneticiliği kaldır") {
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    dpm.removeActiveAdmin(Store.adminComponent(this))
                    root.postDelayed({ render() }, 800)
                })
                root.addView(Ui.button(this, "Vazgeçtim, korumayı geri aç") { Store.cancelUnlock(this); render() })
            }
            ud != null -> {
                root.addView(Ui.note(this, "Kaldırma izni $ud tarihinde (o gün boyunca) açılacak."))
                root.addView(Ui.button(this, "Kaldırma iznini iptal et") { Store.cancelUnlock(this); render() })
            }
            else -> {
                root.addView(Ui.note(this, "Koruma açık: Ayarlar'da bu uygulamayı kapatma/silme ekranları kapanır. Kaldırmak istersen izin iste; izin ertesi gün, bir gün boyunca açılır."))
                root.addView(Ui.button(this, "Kaldırma izni iste (yarın açılır)") {
                    AlertDialog.Builder(this)
                        .setTitle("Emin misin?")
                        .setMessage("${Store.tomorrow()} günü boyunca koruma kapalı olacak ve uygulamayı silebileceksin.")
                        .setPositiveButton("Evet") { _, _ -> Store.requestUnlock(this); render() }
                        .setNegativeButton("Vazgeç", null)
                        .show()
                })
            }
        }
    }

    // ---------- Yardımcılar ----------

    private fun targetsSummary(t: Set<String>): String {
        val apps = t.filter { it.startsWith("a:") }.map { it.substring(2) }.toSet()
        val sites = t.filter { it.startsWith("s:") }.map { it.substring(2) }.toSet()
        val names = LinkedHashSet<String>()
        for (p in Presets.ALL) if (sites.containsAll(p.sites) || apps.any { it in p.apps }) names.add(p.name)
        apps.filter { it !in Presets.allApps }.forEach { names.add(appLabel(it)) }
        sites.filter { it !in Presets.allSites }.forEach { names.add(it) }
        if (names.isEmpty()) return "Hedef seçilmedi"
        return names.joinToString(", ")
    }

    private fun appLabel(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg
    }

    private fun askAdmin() {
        val i = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
            .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, Store.adminComponent(this))
            .putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "Bu izin açıkken Odak Kilidi silinemez. Kaldırmak için uygulamadan izin istemen gerekir.")
        startActivity(i)
    }

    private fun isAccessibilityOn(): Boolean {
        val s = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        return s.split(':').any { it.startsWith("$packageName/") }
    }
}
