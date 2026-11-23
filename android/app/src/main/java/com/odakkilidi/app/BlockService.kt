package com.odakkilidi.app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent

/**
 * Ön plandaki uygulamayı izler:
 *  1) Yasak saatlerde engelli uygulamaları ve tarayıcıdaki engelli siteleri kapatır.
 *  2) Her zaman (kaldırma izni günü hariç) Ayarlar'da bu uygulamayı kapatma/silme ekranlarını kapatır.
 */
class BlockService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())
    private var lastContentCheck = 0L
    private var lastBlockShown = 0L

    // Tarayıcıların adres çubuğu kimlikleri
    private val urlBars = mapOf(
        "com.android.chrome" to "com.android.chrome:id/url_bar",
        "com.chrome.beta" to "com.chrome.beta:id/url_bar",
        "com.chrome.dev" to "com.chrome.dev:id/url_bar",
        "com.sec.android.app.sbrowser" to "com.sec.android.app.sbrowser:id/location_bar_edit_text",
        "com.microsoft.emmx" to "com.microsoft.emmx:id/url_bar",
        "com.brave.browser" to "com.brave.browser:id/url_bar",
        "com.opera.browser" to "com.opera.browser:id/url_field",
        "org.mozilla.firefox" to "org.mozilla.firefox:id/mozac_browser_toolbar_url_view"
    )

    private fun isSettingsLike(pkg: String): Boolean =
        pkg.contains("settings") || pkg.contains("packageinstaller") ||
            pkg.contains("permissioncontroller") || pkg == "com.samsung.android.lool"

    override fun onAccessibilityEvent(e: AccessibilityEvent?) {
        if (e == null) return
        val pkg = e.packageName?.toString() ?: return
        if (pkg == packageName) return
        val isStateChange = e.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED

        // --- Koruma: Ayarlar'da bu uygulamanın sayfası açılırsa kapat ---
        if (isSettingsLike(pkg)) {
            if (isStateChange && Store.guardActive(this)) {
                guardCheck()
                // Sayfa içeriği geç yüklenebilir, biraz sonra tekrar bak
                handler.postDelayed({ guardCheck() }, 400)
                handler.postDelayed({ guardCheck() }, 1200)
            }
            return
        }

        // İçerik değişimlerinde çok sık kontrol etme
        if (!isStateChange) {
            val now = SystemClock.uptimeMillis()
            if (now - lastContentCheck < 700) return
            lastContentCheck = now
        }

        val st = Store.blockState(this)
        if (st.apps.isEmpty() && st.sites.isEmpty()) return

        st.apps[pkg]?.let { rule ->
            block("app", "a:$pkg", rule)
            return
        }

        val barId = urlBars[pkg] ?: return
        if (st.sites.isEmpty()) return
        val url = readUrl(barId) ?: return
        val hit = st.sites.keys.firstOrNull { Rules.hostMatches(url, it) } ?: return
        block("site", "s:$hit", st.sites[hit] ?: "")
    }

    private fun readUrl(viewId: String): String? {
        val root = rootInActiveWindow ?: return null
        return try {
            val nodes = root.findAccessibilityNodeInfosByViewId(viewId)
            nodes.firstOrNull()?.text?.toString()
        } catch (e: Exception) {
            null
        }
    }

    private fun guardCheck() {
        if (!Store.guardActive(this)) return
        val root = rootInActiveWindow ?: return
        val pkg = root.packageName?.toString() ?: return
        if (!isSettingsLike(pkg)) return
        val name = getString(R.string.app_name)
        val found = try {
            root.findAccessibilityNodeInfosByText(name).isNotEmpty()
        } catch (e: Exception) {
            false
        }
        if (found) {
            performGlobalAction(GLOBAL_ACTION_BACK)
            block("guard", "", "")
        }
    }

    private fun block(reason: String, target: String, rule: String) {
        performGlobalAction(GLOBAL_ACTION_HOME)
        val now = SystemClock.uptimeMillis()
        if (now - lastBlockShown < 1500) return
        lastBlockShown = now
        val i = Intent(this, BlockActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra("reason", reason)
            .putExtra("target", target)
            .putExtra("rule", rule)
        try {
            startActivity(i)
        } catch (e: Exception) {
            // yoksay
        }
    }

    override fun onInterrupt() {}
}
