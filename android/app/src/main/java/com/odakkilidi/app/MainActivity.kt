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
import java.time.Instant
import java.time.ZoneId

class MainActivity : Activity() {

    private lateinit var root: LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = "Odak Kilidi"
        val scroll = ScrollView(this)
        scroll.setBackgroundColor(Ui.BG)
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(Ui.dp(this@MainActivity, 16), Ui.dp(this@MainActivity, 12), Ui.dp(this@MainActivity, 16), Ui.dp(this@MainActivity, 48))
        }
        scroll.addView(root)
        setContentView(scroll)
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

        // ---------- Şu anki durum ----------
        val running = Rules.activeRules(active, wm)
        val session = Store.sessionActive(this)
        if (running.isEmpty() && !session) {
            val next = Rules.nextStart(active, wm)
            val txt = if (active.rules.isEmpty()) "Henüz kural yok — aşağıdan ekle"
            else "🔓 Şu an serbest" + (next?.let { "\nSıradaki: ${it.first.name} · ${Rules.fmtWeekMinute((wm + it.second) % WEEK, wm)}" } ?: "")
            root.addView(Ui.banner(this, txt, if (active.rules.isEmpty()) Ui.AMBER else Ui.GREEN))
        } else {
            val lines = running.map { (r, left) -> "• ${r.name} — ${Rules.fmtWeekMinute((wm + left) % WEEK, wm)}'e kadar" }
            root.addView(Ui.banner(this, "🔒 Şu an kilitli\n" + lines.joinToString("\n"), Ui.RED))
        }

        // ---------- Ders modu ----------
        root.addView(Ui.header(this, "📚 Ders modu"))
        if (session) {
            val end = Store.sessionEnd(this)
            val leftMin = ((end - System.currentTimeMillis() + 59_999) / 60_000).toInt()
            val t = Instant.ofEpochMilli(end).atZone(ZoneId.systemDefault()).toLocalTime()
            root.addView(Ui.card(this, "Ders modu açık — ${Rules.fmt(t.hour * 60 + t.minute)}'e kadar (${Rules.fmtDuration(leftMin)})\nKilitli: ${targetsSummary(Rules.dersTargets(active))}", Ui.NAVY))
            root.addView(Ui.button(this, "Süreyi uzat") { askSession(true) })
        } else {
            val dt = Rules.dersTargets(active)
            root.addView(Ui.note(this, if (dt.isEmpty())
                "Ders türünde bir kural ekle; \"Ders başlat\"a basınca o kuralların hedefleri seçtiğin süre boyunca kilitlenir."
            else "Başlatınca kilitlenecekler: ${targetsSummary(dt)}"))
            root.addView(Ui.button(this, "▶  Ders çalışmaya başla", primary = true) { askSession(false) })
        }

        // ---------- Kurallar ----------
        root.addView(Ui.header(this, "🗂️ Kurallar"))
        if (shown.rules.isEmpty()) root.addView(Ui.note(this, "Henüz kural yok."))
        shown.rules.forEachIndexed { idx, r ->
            val isOn = running.any { it.first.id == r.id }
            val kindTxt = if (r.kind == KIND_DERS) "📚 Ders" else "📅 Rutin"
            val when_ = if (r.ranges.isEmpty()) "Sadece \"Ders başlat\" ile"
                else Rules.fmtDays(r.days) + " · " + r.ranges.joinToString(", ") { Rules.fmtRange(it) }
            val body = "$kindTxt · ${r.name}" + (if (isOn) "  🔒" else "") +
                "\n$when_\n${targetsSummary(r.targets())}"
            root.addView(Ui.ruleCard(this, body) {
                startActivity(Intent(this, RuleEditActivity::class.java).putExtra("index", idx))
            })
        }
        root.addView(Ui.button(this, "+  Yeni kural ekle", primary = true) {
            startActivity(Intent(this, RuleEditActivity::class.java).putExtra("index", -1))
        })
        root.addView(Ui.note(this, "Kısıtlamayı ARTIRAN değişiklik hemen geçerli olur. AZALTAN değişiklik (saat kısaltma, hedef çıkarma, kural silme) ertesi gün geçerli olur."))

        // ---------- Bekleyen değişiklik ----------
        Store.pending(this)?.let { (_, date) ->
            root.addView(Ui.card(this, "⏳ Bekleyen değişiklikler $date tarihinde geçerli olacak. Yukarıdaki liste o hâli gösteriyor.", Ui.AMBER))
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

    private fun askSession(extend: Boolean) {
        if (Rules.dersTargets(Store.active(this)).isEmpty()) {
            AlertDialog.Builder(this).setTitle("Önce ders kuralı ekle")
                .setMessage("\"Yeni kural ekle\" → türü 📚 Ders seç → kilitlenecek uygulama ve siteleri işaretle. Saat girmek zorunda değilsin.")
                .setPositiveButton("Tamam", null).show()
            return
        }
        val labels = arrayOf("25 dk", "45 dk", "1 saat", "1,5 saat", "2 saat", "3 saat", "4 saat")
        val mins = intArrayOf(25, 45, 60, 90, 120, 180, 240)
        AlertDialog.Builder(this)
            .setTitle(if (extend) "Ne kadar uzatılsın?" else "Ne kadar ders çalışacaksın?")
            .setItems(labels) { _, which ->
                AlertDialog.Builder(this)
                    .setTitle("${labels[which]} başlatılsın mı?")
                    .setMessage("Ders modu başladıktan sonra erken bitirilemez.")
                    .setPositiveButton("Başlat") { _, _ ->
                        Store.startSession(this, mins[which])
                        render()
                    }
                    .setNegativeButton("Vazgeç", null)
                    .show()
            }
            .show()
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

/** Ortak görünüm parçaları */
object Ui {
    val BG = Color.parseColor("#F4F6FA")
    val NAVY = Color.parseColor("#1F2A44")
    val AMBER = Color.parseColor("#B7791F")
    val RED = Color.parseColor("#C53030")
    val GREEN = Color.parseColor("#2F855A")
    val ACCENT = Color.parseColor("#3B5BDB")

    fun dp(ctx: Context, v: Int) = (v * ctx.resources.displayMetrics.density).toInt()

    fun lp(ctx: Context, top: Int = 0) = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
    ).apply { topMargin = dp(ctx, top) }

    fun header(ctx: Context, t: String) = TextView(ctx).apply {
        text = t
        textSize = 18f
        setTypeface(typeface, Typeface.BOLD)
        setTextColor(NAVY)
        setPadding(0, dp(ctx, 22), 0, dp(ctx, 6))
    }

    fun note(ctx: Context, t: String) = TextView(ctx).apply {
        text = t
        textSize = 13f
        setTextColor(Color.DKGRAY)
        setPadding(0, dp(ctx, 2), 0, dp(ctx, 6))
    }

    private fun rounded(color: Int, ctx: Context, stroke: Int? = null) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(ctx, 12).toFloat()
        if (stroke != null) setStroke(dp(ctx, 1), stroke)
    }

    fun banner(ctx: Context, t: String, color: Int) = TextView(ctx).apply {
        text = t
        textSize = 17f
        setTextColor(Color.WHITE)
        setTypeface(typeface, Typeface.BOLD)
        setPadding(dp(ctx, 16), dp(ctx, 14), dp(ctx, 16), dp(ctx, 14))
        background = rounded(color, ctx)
        layoutParams = lp(ctx, 4)
    }

    fun card(ctx: Context, t: String, color: Int) = TextView(ctx).apply {
        text = t
        textSize = 15f
        setTextColor(Color.WHITE)
        setPadding(dp(ctx, 14), dp(ctx, 12), dp(ctx, 14), dp(ctx, 12))
        background = rounded(color, ctx)
        layoutParams = lp(ctx, 8)
    }

    fun ruleCard(ctx: Context, t: String, onClick: () -> Unit) = TextView(ctx).apply {
        text = t
        textSize = 15f
        setTextColor(NAVY)
        setLineSpacing(0f, 1.15f)
        setPadding(dp(ctx, 14), dp(ctx, 12), dp(ctx, 14), dp(ctx, 12))
        background = rounded(Color.WHITE, ctx, Color.parseColor("#D5DBE8"))
        layoutParams = lp(ctx, 8)
        isClickable = true
        setOnClickListener { onClick() }
    }

    fun button(ctx: Context, t: String, primary: Boolean = false, onClick: () -> Unit) = Button(ctx).apply {
        text = t
        setAllCaps(false)
        textSize = 15f
        if (primary) {
            setTextColor(Color.WHITE)
            background = rounded(ACCENT, ctx)
            gravity = Gravity.CENTER
            setPadding(dp(ctx, 12), dp(ctx, 12), dp(ctx, 12), dp(ctx, 12))
        }
        layoutParams = lp(ctx, 8)
        setOnClickListener { onClick() }
    }
}
