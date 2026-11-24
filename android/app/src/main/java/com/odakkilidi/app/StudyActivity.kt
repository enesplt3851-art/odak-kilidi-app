package com.odakkilidi.app

import android.app.Activity
import android.app.AlertDialog
import android.app.TimePickerDialog
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.NumberPicker
import android.widget.ScrollView
import android.widget.TextView
import java.time.LocalDateTime
import java.time.ZoneId

/** "Ders çalışmaya başla" ekranı: süre + başlangıç + neler kilitlensin. */
class StudyActivity : Activity() {

    private lateinit var hourPicker: NumberPicker
    private lateinit var minPicker: NumberPicker
    private lateinit var startRow: LinearLayout
    private lateinit var summary: TextView
    private lateinit var picker: TargetPicker

    private var startAt: Int? = null // null = şimdi, aksi halde günün dakikası

    private fun dp(v: Int) = Ui.dp(this, v)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = Ui.page(this)
        root.addView(Ui.topBar(this, "📚 Ders çalışmaya başla"))

        // --- Süre ---
        root.addView(Ui.header(this, "⏱️ Ne kadar çalışacaksın?"))
        val pickRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            background = Ui.rounded(this@StudyActivity, Ui.SURFACE, 18, Ui.BORDER)
            setPadding(0, dp(6), 0, dp(6))
        }
        hourPicker = NumberPicker(this).apply {
            minValue = 0; maxValue = 12; value = 2
            wrapSelectorWheel = false
            setOnValueChangedListener { _, _, _ -> updateSummary() }
        }
        minPicker = NumberPicker(this).apply {
            minValue = 0; maxValue = 11
            displayedValues = Array(12) { String.format("%02d", it * 5) }
            value = 0
            setOnValueChangedListener { _, _, _ -> updateSummary() }
        }
        pickRow.addView(hourPicker)
        pickRow.addView(label("saat"))
        pickRow.addView(minPicker)
        pickRow.addView(label("dakika"))
        root.addView(pickRow)

        val quick = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        for ((txt, m) in listOf("25 dk" to 25, "45 dk" to 45, "1 sa" to 60, "2 sa" to 120, "3 sa" to 180, "4 sa" to 240)) {
            quick.addView(Ui.chip(this, txt) {
                hourPicker.value = m / 60
                minPicker.value = (m % 60) / 5
                updateSummary()
            })
        }
        root.addView(quick)

        // --- Başlangıç ---
        root.addView(Ui.header(this, "🕐 Ne zaman başlasın?"))
        startRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        root.addView(startRow)
        renderStart()

        // --- Hedefler ---
        val last = Store.lastSessionTargets(this)
        val initApps = last?.first ?: setOf("com.instagram.android", "com.google.android.youtube")
        val initSites = last?.second ?: setOf("instagram.com", "youtube.com", "youtu.be")
        root.addView(Ui.header(this, "🔒 Neler kilitlensin?"))
        root.addView(Ui.note(this, if (last != null) "Son ders oturumundaki seçimin hazır geldi, istersen değiştir." else "İstediklerini işaretle."))
        picker = TargetPicker(this, initApps, initSites)
        picker.addTo(root)

        // --- Özet + Başlat ---
        summary = TextView(this).apply {
            textSize = 16f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.WHITE)
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = Ui.gradient(this@StudyActivity, Ui.ACCENT, Ui.ACCENT2, 16)
            gravity = Gravity.CENTER
            layoutParams = Ui.lp(this@StudyActivity, 20)
        }
        root.addView(summary)
        root.addView(Ui.button(this, "▶  Başlat", primary = true) { confirmStart() })
        root.addView(Ui.button(this, "Vazgeç") { finish() })
        root.addView(Ui.note(this, "Başladıktan sonra ders oturumu erken bitirilemez ve iptal edilemez."))

        updateSummary()
    }

    private fun minutes(): Int = hourPicker.value * 60 + minPicker.value * 5

    /** Başlangıç zamanı (ms). Seçilen saat geçtiyse yarın. */
    private fun startMillis(): Long {
        val now = LocalDateTime.now()
        val a = startAt ?: return System.currentTimeMillis()
        var t = now.withHour(a / 60).withMinute(a % 60).withSecond(0).withNano(0)
        if (!t.isAfter(now)) t = t.plusDays(1)
        return t.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
    }

    private fun updateSummary() {
        val m = minutes()
        if (m == 0) {
            summary.text = "Süre seç"
            return
        }
        val s = startMillis()
        val e = s + m * 60_000L
        val from = if (startAt == null) "Şimdi" else Rules.fmtMillis(s)
        summary.text = "🔒 $from → ${Rules.fmtMillis(e)}  (${Rules.fmtDuration(m)})"
    }

    private fun renderStart() {
        startRow.removeAllViews()
        startRow.addView(Ui.toggle(this, "Şimdi", startAt == null) {
            startAt = null
            renderStart(); updateSummary()
        })
        val label = startAt?.let { "Saat: ${Rules.fmt(it)}" } ?: "Belirli saatte…"
        startRow.addView(Ui.toggle(this, label, startAt != null) {
            val cur = startAt ?: ((Rules.weekMinuteNow() % 1440) / 15 * 15 + 30) % 1440
            TimePickerDialog(this, { _, h, mi ->
                startAt = h * 60 + mi
                renderStart(); updateSummary()
            }, cur / 60, cur % 60, true).show()
        })
    }

    private fun confirmStart() {
        val m = minutes()
        if (m == 0) {
            alert("Süre seç", "Ders süresi en az 5 dakika olmalı.")
            return
        }
        val apps = picker.apps()
        val sites = picker.sites()
        if (apps.isEmpty() && sites.isEmpty()) {
            alert("Hedef yok", "Kilitlenecek en az bir favori, uygulama ya da site seç.")
            return
        }
        val s = startMillis()
        val e = s + m * 60_000L
        val from = if (startAt == null) "şimdi" else Rules.fmtMillis(s)
        AlertDialog.Builder(this)
            .setTitle("Ders başlasın mı?")
            .setMessage("${Rules.fmtDuration(m)} boyunca ($from → ${Rules.fmtMillis(e)}) seçtiklerin kilitli olacak.\n\nErken bitirilemez, iptal edilemez.")
            .setPositiveButton("Başlat") { _, _ ->
                Store.addSession(this, Session(s, e, apps, sites))
                finish()
            }
            .setNegativeButton("Vazgeç", null)
            .show()
    }

    // ---------- Görünüm yardımcıları ----------

    private fun label(t: String) = TextView(this).apply {
        text = t
        textSize = 16f
        setTextColor(Ui.NAVY)
        setPadding(dp(6), 0, dp(18), 0)
    }

    private fun alert(t: String, msg: String) {
        AlertDialog.Builder(this).setTitle(t).setMessage(msg).setPositiveButton("Tamam", null).show()
    }
}
