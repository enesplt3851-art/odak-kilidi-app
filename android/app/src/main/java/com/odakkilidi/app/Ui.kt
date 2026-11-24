package com.odakkilidi.app

import android.app.Activity
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.SpannableString
import android.text.Spanned
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Ortak görünüm parçaları — koyu, modern tema. */
object Ui {
    private fun c(hex: String) = Color.parseColor(hex)

    // Zeminler
    val BG = c("#0E1322")
    val SURFACE = c("#182036")
    val SURFACE2 = c("#212B46")
    val BORDER = c("#2D3858")
    // Yazılar
    val TEXT = c("#EEF1F8")
    val MUTED = c("#97A1BC")
    val NAVY = TEXT // eski adla kullanılan yerler için: başlık/yazı rengi
    // Vurgular
    val ACCENT = c("#7C5CFF")
    val ACCENT2 = c("#4C8DFF")
    val GREEN = c("#1FA971")
    val RED = c("#E5484D")
    val AMBER = c("#E09A1A")

    fun dp(ctx: Context, v: Int) = (v * ctx.resources.displayMetrics.density).toInt()

    fun lp(ctx: Context, top: Int = 0) = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
    ).apply { topMargin = dp(ctx, top) }

    fun rounded(ctx: Context, color: Int, radius: Int = 16, stroke: Int? = null) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(ctx, radius).toFloat()
        if (stroke != null) setStroke(dp(ctx, 1), stroke)
    }

    fun gradient(ctx: Context, from: Int, to: Int, radius: Int = 18) =
        GradientDrawable(GradientDrawable.Orientation.TL_BR, intArrayOf(from, to)).apply {
            cornerRadius = dp(ctx, radius).toFloat()
        }

    /** Rengi koyulaştır (degrade için). */
    fun darker(color: Int, f: Float = 0.62f) = Color.rgb(
        (Color.red(color) * f).toInt(), (Color.green(color) * f).toInt(), (Color.blue(color) * f).toInt()
    )

    /** Sayfa iskeleti: koyu zemin + kaydırma. İçerik kökü döner. */
    fun page(a: Activity): LinearLayout {
        a.window.statusBarColor = BG
        a.window.navigationBarColor = BG
        val scroll = ScrollView(a).apply { setBackgroundColor(BG); isFillViewport = true }
        val root = LinearLayout(a).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(a, 18), dp(a, 14), dp(a, 18), dp(a, 56))
        }
        scroll.addView(root)
        a.setContentView(scroll)
        return root
    }

    /** Alt sayfalarda üst çubuk: geri oku + başlık. */
    fun topBar(a: Activity, title: String): View = LinearLayout(a).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(0, dp(a, 4), 0, dp(a, 10))
        addView(TextView(a).apply {
            text = "‹"
            textSize = 34f
            setTextColor(TEXT)
            setPadding(dp(a, 4), 0, dp(a, 14), dp(a, 4))
            setOnClickListener { a.finish() }
        })
        addView(TextView(a).apply {
            text = title
            textSize = 22f
            setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD))
            setTextColor(TEXT)
        })
    }

    /** Ana sayfa başlığı. */
    fun hero(ctx: Context, title: String, subtitle: String) = LinearLayout(ctx).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(ctx, 2), dp(ctx, 10), 0, dp(ctx, 14))
        addView(TextView(ctx).apply {
            text = title
            textSize = 30f
            setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD))
            setTextColor(TEXT)
        })
        addView(TextView(ctx).apply {
            text = subtitle
            textSize = 14f
            setTextColor(MUTED)
        })
    }

    fun header(ctx: Context, t: String) = TextView(ctx).apply {
        text = t
        textSize = 17f
        setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD))
        setTextColor(TEXT)
        setPadding(dp(ctx, 2), dp(ctx, 26), 0, dp(ctx, 8))
    }

    fun note(ctx: Context, t: String) = TextView(ctx).apply {
        text = t
        textSize = 13f
        setTextColor(MUTED)
        setLineSpacing(0f, 1.2f)
        setPadding(dp(ctx, 2), dp(ctx, 4), 0, dp(ctx, 6))
    }

    /** İlk satırı kalın ve büyük yazar. */
    private fun titled(t: String): CharSequence {
        val nl = t.indexOf('\n')
        val end = if (nl < 0) t.length else nl
        return SpannableString(t).apply {
            setSpan(StyleSpan(Typeface.BOLD), 0, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            setSpan(RelativeSizeSpan(1.12f), 0, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    /** Büyük durum kartı (degrade). */
    fun banner(ctx: Context, t: String, color: Int) = TextView(ctx).apply {
        text = titled(t)
        textSize = 16f
        setTextColor(Color.WHITE)
        setLineSpacing(0f, 1.25f)
        setPadding(dp(ctx, 20), dp(ctx, 18), dp(ctx, 20), dp(ctx, 18))
        background = gradient(ctx, color, darker(color))
        elevation = dp(ctx, 4).toFloat()
        layoutParams = lp(ctx, 4)
    }

    /** Bilgi kartı: koyu yüzey, renkli kenar. */
    fun card(ctx: Context, t: String, color: Int) = TextView(ctx).apply {
        text = titled(t)
        textSize = 14f
        setTextColor(TEXT)
        setLineSpacing(0f, 1.2f)
        setPadding(dp(ctx, 16), dp(ctx, 14), dp(ctx, 16), dp(ctx, 14))
        background = rounded(ctx, SURFACE, 16, color)
        layoutParams = lp(ctx, 10)
    }

    /** Kural kartı: rozet + ad + saat + hedefler. */
    fun ruleCard(ctx: Context, badge: String, badgeColor: Int, title: String, line1: String, line2: String,
                 locked: Boolean, onClick: () -> Unit) = LinearLayout(ctx).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(ctx, 16), dp(ctx, 14), dp(ctx, 16), dp(ctx, 14))
        background = rounded(ctx, SURFACE, 18, if (locked) RED else BORDER)
        layoutParams = lp(ctx, 10)
        isClickable = true
        setOnClickListener { onClick() }

        val top = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        top.addView(TextView(ctx).apply {
            text = badge
            textSize = 11f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.WHITE)
            setPadding(dp(ctx, 10), dp(ctx, 3), dp(ctx, 10), dp(ctx, 3))
            background = rounded(ctx, badgeColor, 20)
        })
        if (locked) top.addView(TextView(ctx).apply {
            text = "  🔒 şu an aktif"
            textSize = 12f
            setTextColor(RED)
            setTypeface(typeface, Typeface.BOLD)
        })
        top.addView(View(ctx), LinearLayout.LayoutParams(0, 1, 1f))
        top.addView(TextView(ctx).apply { text = "›"; textSize = 24f; setTextColor(MUTED) })
        addView(top)

        addView(TextView(ctx).apply {
            text = title
            textSize = 17f
            setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD))
            setTextColor(TEXT)
            setPadding(0, dp(ctx, 8), 0, dp(ctx, 2))
        })
        addView(TextView(ctx).apply { text = "⏰  $line1"; textSize = 14f; setTextColor(TEXT) })
        addView(TextView(ctx).apply { text = "🔒  $line2"; textSize = 13f; setTextColor(MUTED); setPadding(0, dp(ctx, 2), 0, 0) })
    }

    fun button(ctx: Context, t: String, primary: Boolean = false, onClick: () -> Unit) = Button(ctx).apply {
        text = t
        setAllCaps(false)
        textSize = 15f
        stateListAnimator = null
        setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD))
        gravity = Gravity.CENTER
        setPadding(dp(ctx, 14), dp(ctx, 14), dp(ctx, 14), dp(ctx, 14))
        if (primary) {
            setTextColor(Color.WHITE)
            background = gradient(ctx, ACCENT, ACCENT2, 16)
        } else {
            setTextColor(TEXT)
            background = rounded(ctx, SURFACE, 16, BORDER)
        }
        layoutParams = lp(ctx, 10)
        setOnClickListener { onClick() }
    }

    /** Seçilebilir hap/kutu (gün, tür, başlangıç seçimi). */
    fun toggle(ctx: Context, label: String, on: Boolean, small: Boolean = false, onClick: () -> Unit) =
        TextView(ctx).apply {
            text = label
            gravity = Gravity.CENTER
            textSize = if (small) 13f else 15f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(if (on) Color.WHITE else MUTED)
            background = if (on) gradient(ctx, ACCENT, ACCENT2, 12) else rounded(ctx, SURFACE, 12, BORDER)
            setPadding(0, dp(ctx, if (small) 11 else 13), 0, dp(ctx, if (small) 11 else 13))
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                setMargins(dp(ctx, 3), dp(ctx, 3), dp(ctx, 3), dp(ctx, 3))
            }
            setOnClickListener { onClick() }
        }

    /** Küçük hızlı seçim çipi. */
    fun chip(ctx: Context, t: String, onClick: () -> Unit) = TextView(ctx).apply {
        text = t
        textSize = 13f
        gravity = Gravity.CENTER
        setTextColor(TEXT)
        setTypeface(typeface, Typeface.BOLD)
        background = rounded(ctx, SURFACE2, 20, BORDER)
        setPadding(0, dp(ctx, 9), 0, dp(ctx, 9))
        layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
            setMargins(dp(ctx, 3), dp(ctx, 6), dp(ctx, 3), dp(ctx, 3))
        }
        setOnClickListener { onClick() }
    }

    /** Büyük saat butonu (09:00 gibi). */
    fun timeBox(ctx: Context, t: String, onClick: () -> Unit) = TextView(ctx).apply {
        text = t
        textSize = 22f
        gravity = Gravity.CENTER
        setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD))
        setTextColor(TEXT)
        background = rounded(ctx, SURFACE2, 14, ACCENT)
        setPadding(dp(ctx, 18), dp(ctx, 10), dp(ctx, 18), dp(ctx, 10))
        setOnClickListener { onClick() }
    }

    fun styleField(ctx: Context, e: EditText) {
        e.setTextColor(TEXT)
        e.setHintTextColor(MUTED)
        e.textSize = 16f
        e.background = rounded(ctx, SURFACE, 14, BORDER)
        e.setPadding(dp(ctx, 14), dp(ctx, 12), dp(ctx, 14), dp(ctx, 12))
        e.layoutParams = lp(ctx, 2)
    }

    fun styleCheck(cb: CheckBox) {
        cb.setTextColor(TEXT)
        cb.buttonTintList = ColorStateList.valueOf(ACCENT)
    }
}
