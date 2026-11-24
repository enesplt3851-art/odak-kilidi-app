package com.odakkilidi.app

import android.app.Activity
import android.app.AlertDialog
import android.app.TimePickerDialog
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Bir kuralı ekleme / düzenleme ekranı. */
class RuleEditActivity : Activity() {

    private var index = -1
    private lateinit var base: Config
    private var oldRule: Rule? = null

    private var kind = KIND_RUTIN
    private val days = BooleanArray(7) { true }
    private val ranges = mutableListOf<IntArray>() // [başlangıç, bitiş] dakika
    private lateinit var picker: TargetPicker

    private lateinit var nameEdit: EditText
    private lateinit var kindRow: LinearLayout
    private lateinit var kindNote: TextView
    private lateinit var daysRow: LinearLayout
    private lateinit var rangesBox: LinearLayout

    private fun dp(v: Int) = Ui.dp(this, v)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        index = intent.getIntExtra("index", -1)
        base = Store.editable(this)
        oldRule = base.rules.getOrNull(index)

        val r = oldRule
        if (r != null) {
            kind = r.kind
            for (i in 0 until 7) days[i] = r.days[i]
            r.ranges.forEach { ranges.add(intArrayOf(it.start, it.end)) }
        } else {
            ranges.add(intArrayOf(9 * 60, 12 * 60))
        }
        picker = TargetPicker(this, r?.apps ?: emptySet(), r?.sites ?: emptySet())

        val root = Ui.page(this)
        root.addView(Ui.topBar(this, if (oldRule == null) "Yeni kural" else "Kuralı düzenle"))

        // --- Ad ---
        root.addView(Ui.header(this, "✏️ Kural adı"))
        nameEdit = EditText(this).apply {
            hint = "örn. Sabah rutini, Matematik çalışma"
            setText(r?.name ?: "")
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
        }
        Ui.styleField(this, nameEdit)
        root.addView(nameEdit)

        // --- Tür ---
        root.addView(Ui.header(this, "Tür"))
        kindRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        root.addView(kindRow)
        kindNote = Ui.note(this, "")
        root.addView(kindNote)

        // --- Günler ---
        root.addView(Ui.header(this, "📆 Günler"))
        daysRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        root.addView(daysRow)
        val quick = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        quick.addView(Ui.chip(this, "Her gün") { for (i in 0 until 7) days[i] = true; renderDays() })
        quick.addView(Ui.chip(this, "Hafta içi") { for (i in 0 until 7) days[i] = i < 5; renderDays() })
        quick.addView(Ui.chip(this, "Hafta sonu") { for (i in 0 until 7) days[i] = i >= 5; renderDays() })
        root.addView(quick)

        // --- Saatler ---
        root.addView(Ui.header(this, "⏰ Saatler"))
        root.addView(Ui.note(this, "Saate dokunarak seç. Başlangıç ile bitiş aynıysa tüm gün. Bitiş başlangıçtan küçükse gece yarısını aşar (23:00 → 07:00)."))
        rangesBox = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(rangesBox)
        root.addView(Ui.button(this, "+  Saat aralığı ekle") {
            val last = ranges.lastOrNull()
            val s = if (last != null) last[1] else 9 * 60
            ranges.add(intArrayOf(s, (s + 60) % 1440))
            renderRanges()
        })

        // --- Hedefler ---
        picker.addTo(root)

        // --- Butonlar ---
        root.addView(Ui.button(this, "Kaydet", primary = true) { save() })
        if (oldRule != null) root.addView(Ui.button(this, "🗑️ Kuralı sil") { delete() })
        root.addView(Ui.button(this, "Vazgeç") { finish() })

        renderKind()
        renderDays()
        renderRanges()
    }

    // ---------------- Bölümler ----------------

    private fun renderKind() {
        kindRow.removeAllViews()
        kindRow.addView(Ui.toggle(this, "📅 Rutin", kind == KIND_RUTIN) { kind = KIND_RUTIN; renderKind() })
        kindRow.addView(Ui.toggle(this, "📚 Ders", kind == KIND_DERS) { kind = KIND_DERS; renderKind() })
        kindNote.text = if (kind == KIND_RUTIN)
            "Seçtiğin gün ve saatlerde her hafta otomatik kilitlenir."
        else
            "Haftalık sabit ders saatlerin (örn. hafta içi 14:00–17:00). Anlık ders için ana ekrandaki \"Ders çalışmaya başla\" butonunu kullan."
    }

    private fun renderDays() {
        daysRow.removeAllViews()
        for (i in 0 until 7) {
            daysRow.addView(Ui.toggle(this, Rules.DAY_NAMES[i], days[i], small = true) {
                days[i] = !days[i]
                renderDays()
            })
        }
    }

    private fun renderRanges() {
        rangesBox.removeAllViews()
        if (ranges.isEmpty()) {
            rangesBox.addView(Ui.note(this, "Saat aralığı ekle."))
        }
        ranges.forEachIndexed { i, rg ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = Ui.lp(this@RuleEditActivity, 6)
            }
            row.addView(timeButton(rg[0]) { m -> rg[0] = m; renderRanges() })
            row.addView(TextView(this).apply {
                text = "→"
                textSize = 18f
                setTextColor(Ui.MUTED)
                setPadding(dp(10), 0, dp(10), 0)
            })
            row.addView(timeButton(rg[1]) { m -> rg[1] = m; renderRanges() })
            row.addView(TextView(this).apply {
                text = if (rg[0] == rg[1]) "tüm gün" else Rules.fmtDuration(Rules.rangeLen(Range(rg[0], rg[1])))
                textSize = 13f
                setTextColor(Ui.MUTED)
                setPadding(dp(10), 0, 0, 0)
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            })
            row.addView(TextView(this).apply {
                text = "✕"
                textSize = 18f
                setTextColor(Ui.RED)
                setPadding(dp(14), dp(8), dp(6), dp(8))
                setOnClickListener { ranges.removeAt(i); renderRanges() }
            })
            rangesBox.addView(row)
        }
    }

    private fun timeButton(m: Int, onPick: (Int) -> Unit) = Ui.timeBox(this, Rules.fmt(m)) {
        TimePickerDialog(this, { _, h, min -> onPick(h * 60 + min) }, m / 60, m % 60, true).show()
    }

    // ---------------- Kaydet / Sil ----------------

    private fun save() {
        val name = nameEdit.text.toString().trim().ifEmpty { if (kind == KIND_DERS) "Ders" else "Rutin" }
        if (ranges.isEmpty()) {
            alert("Saat eksik", "En az bir saat aralığı ekle. (Anlık ders için ana ekrandaki \"Ders çalışmaya başla\" butonunu kullan.)")
            return
        }
        if (ranges.isNotEmpty() && days.none { it }) {
            alert("Gün eksik", "En az bir gün seç.")
            return
        }
        val apps = picker.apps()
        val sites = picker.sites()
        if (apps.isEmpty() && sites.isEmpty()) {
            alert("Hedef yok", "En az bir favori, uygulama ya da site seç.")
            return
        }
        val rule = Rule(
            id = oldRule?.id ?: Rules.newId(),
            name = name,
            kind = kind,
            days = days.toList(),
            ranges = ranges.map { Range(it[0], it[1]) },
            apps = apps,
            sites = sites
        )
        val list = base.rules.toMutableList()
        if (index in list.indices) list[index] = rule else list.add(rule)
        showResult(Store.save(this, Config(list)))
    }

    private fun delete() {
        AlertDialog.Builder(this)
            .setTitle("Kural silinsin mi?")
            .setMessage("Silmek kısıtlamayı azalttığı için ertesi gün geçerli olur (kural henüz hiç geçerli olmadıysa hemen silinir).")
            .setPositiveButton("Sil") { _, _ ->
                val list = base.rules.toMutableList()
                if (index in list.indices) list.removeAt(index)
                showResult(Store.save(this, Config(list)))
            }
            .setNegativeButton("Vazgeç", null)
            .show()
    }

    private fun showResult(immediate: Boolean) {
        val (t, msg) = if (immediate)
            "Kaydedildi ✅" to "Değişiklik hemen geçerli oldu."
        else
            "Yarın geçerli olacak ⏳" to "Bu değişiklik kısıtlamayı azalttığı için ${Store.tomorrow()} tarihinde (gece 00:00'dan sonra) geçerli olacak. Bugün eski kurallar devam ediyor."
        AlertDialog.Builder(this)
            .setTitle(t)
            .setMessage(msg)
            .setCancelable(false)
            .setPositiveButton("Tamam") { _, _ -> finish() }
            .show()
    }

    private fun alert(t: String, msg: String) {
        AlertDialog.Builder(this).setTitle(t).setMessage(msg).setPositiveButton("Tamam", null).show()
    }
}
