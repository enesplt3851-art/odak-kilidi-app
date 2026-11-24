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
            val now = System.currentTimeMillis()
            val sEnd = Store.activeSessions(this).filter { target in it.targets() }.maxOfOrNull { it.end } ?: now
            val bySession = ((sEnd - now + 59_999) / 60_000).toInt()
            val d = maxOf(byRules, bySession)
            left = if (d >= 7 * 1440) "Sürekli kilitli." else
                "Açılmasına ${Rules.fmtDuration(d)} var (${Rules.fmtWeekMinute((wm + d) % WEEK, wm)})."
        }

        window.statusBarColor = Ui.BG
        window.navigationBarColor = Ui.BG
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            background = android.graphics.drawable.GradientDrawable(
                android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.parseColor("#2A1F5C"), Ui.BG)
            )
            setPadding(dp(32), dp(32), dp(32), dp(32))
        }
        box.addView(TextView(this).apply {
            text = "🔒"
            textSize = 72f
            gravity = Gravity.CENTER
        })
        box.addView(TextView(this).apply {
            text = message
            textSize = 22f
            setTextColor(Ui.TEXT)
            setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD))
            gravity = Gravity.CENTER
            setLineSpacing(0f, 1.2f)
            setPadding(0, dp(18), 0, dp(10))
        })
        if (left.isNotEmpty()) box.addView(TextView(this).apply {
            text = left
            textSize = 15f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = Ui.rounded(this@BlockActivity, Ui.SURFACE2, 20, Ui.ACCENT)
            setPadding(dp(18), dp(10), dp(18), dp(10))
        })
        box.addView(TextView(this).apply {
            text = "Odaklan. Gerisi bekleyebilir. 💪"
            textSize = 14f
            setTextColor(Ui.MUTED)
            gravity = Gravity.CENTER
            setPadding(0, dp(28), 0, dp(20))
        })
        box.addView(Ui.button(this, "Ana ekrana dön", primary = true) { goHome() }.apply {
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
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
