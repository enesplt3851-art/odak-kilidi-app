package com.odakkilidi.app

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout

/** "Neler kilitlensin?" bölümü: favoriler + diğer uygulamalar + diğer siteler. */
class TargetPicker(private val act: Activity, initialApps: Set<String>, initialSites: Set<String>) {

    private val selected: List<Preset> = Presets.selectedFor(initialApps, initialSites)
    private val presetChecks = mutableListOf<Pair<Preset, CheckBox>>()
    private val otherApps = LinkedHashSet<String>()
    private val customSites: Set<String>
    private lateinit var otherAppsBtn: Button
    private lateinit var sitesEdit: EditText

    init {
        otherApps.addAll(initialApps - selected.flatMap { it.apps }.toSet())
        customSites = initialSites - selected.flatMap { it.sites }.toSet()
    }

    fun addTo(root: LinearLayout) {
        root.addView(Ui.header(act, "⭐ Favoriler"))
        root.addView(Ui.note(act, "İşaretlediğinin hem uygulaması hem sitesi kilitlenir."))
        val box = LinearLayout(act).apply {
            orientation = LinearLayout.VERTICAL
            background = Ui.rounded(act, Ui.SURFACE, 18, Ui.BORDER)
            setPadding(Ui.dp(act, 12), Ui.dp(act, 6), Ui.dp(act, 12), Ui.dp(act, 6))
            layoutParams = Ui.lp(act, 2)
        }
        root.addView(box)
        for (start in Presets.ALL.indices step 2) {
            val row = LinearLayout(act).apply { orientation = LinearLayout.HORIZONTAL }
            box.addView(row)
            for (p in Presets.ALL.subList(start, minOf(start + 2, Presets.ALL.size))) {
                val cb = CheckBox(act).apply {
                    text = p.name
                    textSize = 15f
                    isChecked = p in selected
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    setPadding(0, Ui.dp(act, 6), 0, Ui.dp(act, 6))
                }
                Ui.styleCheck(cb)
                row.addView(cb)
                presetChecks.add(p to cb)
            }
        }

        root.addView(Ui.header(act, "📱 Diğer uygulamalar"))
        otherAppsBtn = Ui.button(act, "") { pickApps() }
        root.addView(otherAppsBtn)
        updateBtn()

        root.addView(Ui.header(act, "🌐 Diğer siteler"))
        root.addView(Ui.note(act, "Her satıra bir site (örn. 9gag.com). Alt alan adları da engellenir."))
        sitesEdit = EditText(act).apply {
            hint = "ornek.com"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            minLines = 2
            gravity = Gravity.TOP or Gravity.START
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
            setText(customSites.sorted().joinToString("\n"))
        }
        Ui.styleField(act, sitesEdit)
        sitesEdit.gravity = Gravity.TOP or Gravity.START
        root.addView(sitesEdit)
    }

    fun apps(): Set<String> =
        presetChecks.filter { it.second.isChecked }.flatMap { it.first.apps }.toSet() + otherApps

    fun sites(): Set<String> =
        presetChecks.filter { it.second.isChecked }.flatMap { it.first.sites }.toSet() +
            Rules.parseSites(sitesEdit.text.toString())

    private fun updateBtn() {
        otherAppsBtn.text = if (otherApps.isEmpty()) "Uygulama seç" else "Uygulama seç (${otherApps.size} seçili)"
    }

    private fun pickApps() {
        val pm = act.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val list = pm.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != act.packageName && it.first !in Presets.allApps }
            .distinctBy { it.first }
            .toMutableList()
        for (s in otherApps) if (list.none { it.first == s }) list.add(s to "$s (yüklü değil)")
        list.sortWith(compareBy<Pair<String, String>>({ it.first !in otherApps }, { it.second.lowercase() }))
        val labels = list.map { it.second }.toTypedArray()
        val checked = BooleanArray(list.size) { list[it].first in otherApps }
        AlertDialog.Builder(act)
            .setTitle("Kilitlenecek uygulamalar")
            .setMultiChoiceItems(labels, checked) { _, which, isChecked -> checked[which] = isChecked }
            .setPositiveButton("Tamam") { _, _ ->
                otherApps.clear()
                list.forEachIndexed { i, p -> if (checked[i]) otherApps.add(p.first) }
                updateBtn()
            }
            .setNegativeButton("Vazgeç", null)
            .show()
    }
}
