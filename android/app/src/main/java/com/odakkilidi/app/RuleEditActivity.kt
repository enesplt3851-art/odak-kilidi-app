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
    private val otherApps = LinkedHashSet<String>()
    private val presetChecks = mutableListOf<Pair<Preset, CheckBox>>()

    private lateinit var nameEdit: EditText
    private lateinit var kindRow: LinearLayout
    private lateinit var kindNote: TextView
    private lateinit var daysRow: LinearLayout
    private lateinit var rangesBox: LinearLayout
    private lateinit var otherAppsBtn: Button
    private lateinit var sitesEdit: EditText

    private fun dp(v: Int) = Ui.dp(this, v)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        index = intent.getIntExtra("index", -1)
        base = Store.editable(this)
        oldRule = base.rules.getOrNull(index)
        title = if (oldRule == null) "Yeni kural" else "Kuralı düzenle"

        val r = oldRule
        val selectedPresets: List<Preset>
        if (r != null) {
            kind = r.kind
            for (i in 0 until 7) days[i] = r.days[i]
            r.ranges.forEach { ranges.add(intArrayOf(it.start, it.end)) }
            selectedPresets = Presets.selectedIn(r)
            otherApps.addAll(r.apps - selectedPresets.flatMap { it.apps }.toSet())
        } else {
            ranges.add(intArrayOf(9 * 60, 12 * 60))
            selectedPresets = emptyList()
        }

        val scroll = ScrollView(this)
        scroll.setBackgroundColor(Ui.BG)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(8), dp(16), dp(48))
        }
        scroll.addView(root)

        // --- Ad ---
        root.addView(Ui.header(this, "✏️ Kural adı"))
        nameEdit = EditText(this).apply {
            hint = "örn. Sabah rutini, Matematik çalışma"
            setText(r?.name ?: "")
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
        }
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
        quick.addView(smallButton("Her gün") { for (i in 0 until 7) days[i] = true; renderDays() })
        quick.addView(smallButton("Hafta içi") { for (i in 0 until 7) days[i] = i < 5; renderDays() })
        quick.addView(smallButton("Hafta sonu") { for (i in 0 until 7) days[i] = i >= 5; renderDays() })
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

        // --- Favoriler ---
        root.addView(Ui.header(this, "⭐ Favoriler (uygulama + site birlikte)"))
        for (start in Presets.ALL.indices step 2) {
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            root.addView(row)
            for (p in Presets.ALL.subList(start, minOf(start + 2, Presets.ALL.size))) {
                val cb = CheckBox(this).apply {
                    text = p.name
                    textSize = 15f
                    isChecked = p in selectedPresets
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                }
                row.addView(cb)
                presetChecks.add(p to cb)
            }
        }

        // --- Diğer uygulamalar ---
        root.addView(Ui.header(this, "📱 Diğer uygulamalar"))
        otherAppsBtn = Ui.button(this, "") { pickApps() }
        root.addView(otherAppsBtn)
        updateOtherAppsBtn()

        // --- Diğer siteler ---
        root.addView(Ui.header(this, "🌐 Diğer siteler"))
        root.addView(Ui.note(this, "Her satıra bir site (örn. 9gag.com). Alt alan adları da engellenir."))
        sitesEdit = EditText(this).apply {
            hint = "ornek.com"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            minLines = 2
            gravity = Gravity.TOP or Gravity.START
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
            val custom = (r?.sites ?: emptySet()) - selectedPresets.flatMap { it.sites }.toSet()
            setText(custom.sorted().joinToString("\n"))
        }
        root.addView(sitesEdit)

        // --- Butonlar ---
        root.addView(Ui.button(this, "Kaydet", primary = true) { save() })
        if (oldRule != null) root.addView(Ui.button(this, "🗑️ Kuralı sil") { delete() })
        root.addView(Ui.button(this, "Vazgeç") { finish() })

        setContentView(scroll)
        renderKind()
        renderDays()
        renderRanges()
    }

    // ---------------- Bölümler ----------------

    private fun renderKind() {
        kindRow.removeAllViews()
        kindRow.addView(toggle("📅 Rutin", kind == KIND_RUTIN, 1f) { kind = KIND_RUTIN; renderKind() })
        kindRow.addView(toggle("📚 Ders", kind == KIND_DERS, 1f) { kind = KIND_DERS; renderKind() })
        kindNote.text = if (kind == KIND_RUTIN)
            "Seçtiğin gün ve saatlerde her hafta otomatik kilitlenir."
        else
            "Ana ekrandaki \"Ders başlat\" butonuyla kilitlenir. İstersen saat de ekle, o saatlerde otomatik kilitlenir; saatleri silersen sadece butonla çalışır."
    }

    private fun renderDays() {
        daysRow.removeAllViews()
        for (i in 0 until 7) {
            daysRow.addView(toggle(Rules.DAY_NAMES[i], days[i], 1f, small = true) {
                days[i] = !days[i]
                renderDays()
            })
        }
    }

    private fun renderRanges() {
        rangesBox.removeAllViews()
        if (ranges.isEmpty()) {
            rangesBox.addView(Ui.note(this, if (kind == KIND_DERS) "Saat yok — sadece \"Ders başlat\" ile çalışır." else "Saat aralığı ekle."))
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
                setTextColor(Ui.NAVY)
                setPadding(dp(10), 0, dp(10), 0)
            })
            row.addView(timeButton(rg[1]) { m -> rg[1] = m; renderRanges() })
            row.addView(TextView(this).apply {
                text = if (rg[0] == rg[1]) "tüm gün" else Rules.fmtDuration(Rules.rangeLen(Range(rg[0], rg[1])))
                textSize = 13f
                setTextColor(Color.GRAY)
                setPadding(dp(10), 0, 0, 0)
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            })
            row.addView(Button(this).apply {
                text = "✕"
                setOnClickListener { ranges.removeAt(i); renderRanges() }
            })
            rangesBox.addView(row)
        }
    }

    private fun timeButton(m: Int, onPick: (Int) -> Unit) = Button(this).apply {
        text = Rules.fmt(m)
        textSize = 20f
        setTypeface(typeface, Typeface.BOLD)
        setTextColor(Ui.ACCENT)
        background = GradientDrawable().apply {
            setColor(Color.WHITE)
            cornerRadius = dp(10).toFloat()
            setStroke(dp(1), Ui.ACCENT)
        }
        setPadding(dp(16), dp(8), dp(16), dp(8))
        setOnClickListener {
            TimePickerDialog(this@RuleEditActivity, { _, h, min -> onPick(h * 60 + min) }, m / 60, m % 60, true).show()
        }
    }

    private fun toggle(label: String, on: Boolean, weight: Float, small: Boolean = false, onClick: () -> Unit) =
        TextView(this).apply {
            text = label
            gravity = Gravity.CENTER
            textSize = if (small) 13f else 15f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(if (on) Color.WHITE else Ui.NAVY)
            background = GradientDrawable().apply {
                setColor(if (on) Ui.ACCENT else Color.WHITE)
                cornerRadius = dp(10).toFloat()
                setStroke(dp(1), if (on) Ui.ACCENT else Color.parseColor("#C9D1E3"))
            }
            setPadding(0, dp(if (small) 10 else 12), 0, dp(if (small) 10 else 12))
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, weight).apply {
                setMargins(dp(3), dp(3), dp(3), dp(3))
            }
            setOnClickListener { onClick() }
        }

    private fun smallButton(label: String, onClick: () -> Unit) = Button(this).apply {
        text = label
        setAllCaps(false)
        textSize = 13f
        layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        setOnClickListener { onClick() }
    }

    // ---------------- Diğer uygulamalar ----------------

    private fun updateOtherAppsBtn() {
        otherAppsBtn.text = if (otherApps.isEmpty()) "Uygulama seç" else "Uygulama seç (${otherApps.size} seçili)"
    }

    private fun pickApps() {
        val pm = packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val list = pm.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != packageName && it.first !in Presets.allApps }
            .distinctBy { it.first }
            .toMutableList()
        for (s in otherApps) if (list.none { it.first == s }) list.add(s to "$s (yüklü değil)")
        list.sortWith(compareBy<Pair<String, String>>({ it.first !in otherApps }, { it.second.lowercase() }))
        val labels = list.map { it.second }.toTypedArray()
        val checked = BooleanArray(list.size) { list[it].first in otherApps }
        AlertDialog.Builder(this)
            .setTitle("Kilitlenecek uygulamalar")
            .setMultiChoiceItems(labels, checked) { _, which, isChecked -> checked[which] = isChecked }
            .setPositiveButton("Tamam") { _, _ ->
                otherApps.clear()
                list.forEachIndexed { i, p -> if (checked[i]) otherApps.add(p.first) }
                updateOtherAppsBtn()
            }
            .setNegativeButton("Vazgeç", null)
            .show()
    }

    // ---------------- Kaydet / Sil ----------------

    private fun save() {
        val name = nameEdit.text.toString().trim().ifEmpty { if (kind == KIND_DERS) "Ders" else "Rutin" }
        if (kind == KIND_RUTIN && ranges.isEmpty()) {
            alert("Saat eksik", "Rutin kural için en az bir saat aralığı ekle.")
            return
        }
        if (ranges.isNotEmpty() && days.none { it }) {
            alert("Gün eksik", "En az bir gün seç.")
            return
        }
        val chosen = presetChecks.filter { it.second.isChecked }.map { it.first }
        val apps = chosen.flatMap { it.apps }.toSet() + otherApps
        val sites = chosen.flatMap { it.sites }.toSet() + Rules.parseSites(sitesEdit.text.toString())
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
