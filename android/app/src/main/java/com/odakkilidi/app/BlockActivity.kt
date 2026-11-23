package com.odakkilidi.app

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Engellenen bir şey açılınca gösterilen ekran. */
class BlockActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        render(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        render(intent)
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun render(i: Intent?) {
        val reason = i?.getStringExtra("reason") ?: "app"
        val target = i?.getStringExtra("target") ?: ""
        val rule = i?.getStringExtra("rule") ?: ""
        val label = when {
            target.startsWith("a:") -> Presets.nameForApp(target.substring(2)) ?: appLabel(target.substring(2))
            target.startsWith("s:") -> Presets.nameForSite(target.substring(2)) ?: target.substring(2)
            else -> ""
        }

        val message = when (reason) {
            "guard" -> "Odak Kilidi korunuyor.\n\nKapatmak ya da silmek için uygulamadan \"Kaldırma izni\" iste. İzin ertesi gün açılır."
            else -> "$label şu an kilitli" + (if (rule.isNotEmpty()) "\n($rule)" else "")
        }

        var left = ""
        if (reason != "guard" && target.isNotEmpty()) {
            val wm = Rules.weekMinuteNow()
            val cfg = Store.active(this)
            val byRules = Rules.minutesUntilFree(cfg, target, wm) ?: (7 * 1440)
            val bySession = if (Store.sessionActive(this) && target in Rules.dersTargets(cfg))
                ((Store.sessionEnd(this) - System.currentTimeMillis() + 59_999) / 60_000).toInt() else 0
            val d = maxOf(byRules, bySession)
            left = if (d >= 7 * 1440) "Sürekli kilitli." else
                "Açılmasına ${Rules.fmtDuration(d)} var (${Rules.fmtWeekMinute((wm + d) % WEEK, wm)})."
        }

        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#1F2A44"))
            setPadding(dp(32), dp(32), dp(32), dp(32))
        }
        box.addView(TextView(this).apply {
            text = "🔒"
            textSize = 64f
            gravity = Gravity.CENTER
        })
        box.addView(TextView(this).apply {
            text = message
            textSize = 20f
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(0, dp(16), 0, dp(8))
        })
        box.addView(TextView(this).apply {
            text = left
            textSize = 16f
            setTextColor(Color.parseColor("#FFC857"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(24))
        })
        box.addView(Button(this).apply {
            text = "Ana ekrana dön"
            setOnClickListener { goHome() }
        })
        setContentView(box)
    }

    private fun appLabel(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg
    }

    private fun goHome() {
        startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        goHome()
    }
}
