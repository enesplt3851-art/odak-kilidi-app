package com.odakkilidi.app

import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDateTime
import java.util.BitSet
import java.util.UUID

/** Gün içi dakika aralığı (0..1439). start == end -> tüm gün. start > end -> gece yarısını aşar. */
data class Range(val start: Int, val end: Int)

const val KIND_RUTIN = "rutin"
const val KIND_DERS = "ders"
const val WEEK = 7 * 1440

data class Rule(
    val id: String,
    val name: String,
    val kind: String,              // "rutin" veya "ders"
    val days: List<Boolean>,       // 7 eleman: Pzt..Paz
    val ranges: List<Range>,
    val apps: Set<String>,         // paket adları
    val sites: Set<String>         // alan adları
) {
    fun targets(): Set<String> = apps.map { "a:$it" }.toSet() + sites.map { "s:$it" }.toSet()
}

data class Config(val rules: List<Rule>)

/** Ders oturumu: başlangıç/bitiş (ms) ve o an seçilen hedefler. Erken bitirilemez. */
data class Session(val start: Long, val end: Long, val apps: Set<String>, val sites: Set<String>) {
    fun targets(): Set<String> = apps.map { "a:$it" }.toSet() + sites.map { "s:$it" }.toSet()
}

/** Tek tıkla seçilen favori platformlar: uygulama + site birlikte. */
data class Preset(val name: String, val apps: Set<String>, val sites: Set<String>)

object Presets {
    val ALL = listOf(
        Preset("Instagram", setOf("com.instagram.android", "com.instagram.lite"), setOf("instagram.com")),
        Preset("YouTube", setOf("com.google.android.youtube"), setOf("youtube.com", "youtu.be")),
        Preset("TikTok", setOf("com.zhiliaoapp.musically", "com.ss.android.ugc.trill"), setOf("tiktok.com")),
        Preset("X (Twitter)", setOf("com.twitter.android"), setOf("x.com", "twitter.com")),
        Preset("Facebook", setOf("com.facebook.katana", "com.facebook.lite"), setOf("facebook.com")),
        Preset("Reddit", setOf("com.reddit.frontpage"), setOf("reddit.com")),
        Preset("Twitch", setOf("tv.twitch.android.app"), setOf("twitch.tv")),
        Preset("Netflix", setOf("com.netflix.mediaclient"), setOf("netflix.com")),
        Preset("Snapchat", setOf("com.snapchat.android"), setOf("snapchat.com")),
        Preset("Discord", setOf("com.discord"), setOf("discord.com")),
        Preset("Pinterest", setOf("com.pinterest"), setOf("pinterest.com")),
        Preset("WhatsApp", setOf("com.whatsapp"), setOf("web.whatsapp.com"))
    )
    val allApps: Set<String> = ALL.flatMap { it.apps }.toSet()
    val allSites: Set<String> = ALL.flatMap { it.sites }.toSet()

    fun selectedIn(r: Rule): List<Preset> = selectedFor(r.apps, r.sites)

    fun selectedFor(apps: Set<String>, sites: Set<String>): List<Preset> =
        ALL.filter { p -> sites.any { it in p.sites } || apps.any { it in p.apps } }

    fun nameForApp(pkg: String): String? = ALL.firstOrNull { pkg in it.apps }?.name
    fun nameForSite(site: String): String? = ALL.firstOrNull { site in it.sites }?.name
}

/** Şu an engellenenler: hedef -> sebep (kural adı) */
data class BlockState(val apps: Map<String, String>, val sites: Map<String, String>)

object Rules {
    val DAY_NAMES = listOf("Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz")

    fun newId(): String = UUID.randomUUID().toString().substring(0, 8)

    fun weekMinuteNow(): Int {
        val n = LocalDateTime.now()
        return (n.dayOfWeek.value - 1) * 1440 + n.hour * 60 + n.minute
    }

    fun rangeLen(r: Range): Int {
        val d = ((r.end - r.start) % 1440 + 1440) % 1440
        return if (d == 0) 1440 else d
    }

    /** Kural, haftanın bu dakikasında yasak mı? (Aralık, başladığı güne aittir.) */
    fun covers(r: Rule, wm: Int): Boolean {
        for (d in 0 until 7) {
            if (!r.days[d]) continue
            for (g in r.ranges) {
                val off = ((wm - (d * 1440 + g.start)) % WEEK + WEEK) % WEEK
                if (off < rangeLen(g)) return true
            }
        }
        return false
    }

    fun mask(r: Rule): BitSet {
        val b = BitSet(WEEK)
        for (d in 0 until 7) {
            if (!r.days[d]) continue
            for (g in r.ranges) {
                val st = d * 1440 + g.start
                for (i in 0 until rangeLen(g)) b.set((st + i) % WEEK)
            }
        }
        return b
    }

    /** Şu an hangi uygulama/siteler engelli? */
    fun blockState(c: Config, wm: Int, sessions: List<Session>): BlockState {
        val apps = HashMap<String, String>()
        val sites = HashMap<String, String>()
        for (r in c.rules) {
            if (covers(r, wm)) {
                r.apps.forEach { apps.putIfAbsent(it, r.name) }
                r.sites.forEach { sites.putIfAbsent(it, r.name) }
            }
        }
        for (ss in sessions) {
            ss.apps.forEach { apps.putIfAbsent(it, "Ders modu") }
            ss.sites.forEach { sites.putIfAbsent(it, "Ders modu") }
        }
        return BlockState(apps, sites)
    }

    /** Bir hedefin (a:paket / s:site) kurallar yüzünden kaç dakika daha kilitli kalacağı. */
    fun minutesUntilFree(c: Config, target: String, wm: Int): Int? {
        val rs = c.rules.filter { target in it.targets() }
        for (i in 0..WEEK) {
            val m = (wm + i) % WEEK
            if (rs.none { covers(it, m) }) return i
        }
        return null
    }

    /** Şu an aktif olan kurallar ve her birinin biteceği dakika sayısı. */
    fun activeRules(c: Config, wm: Int): List<Pair<Rule, Int>> =
        c.rules.filter { covers(it, wm) }.map { r ->
            var i = 1
            while (i <= WEEK && covers(r, (wm + i) % WEEK)) i++
            r to i
        }

    /** Sıradaki başlayacak kural ve kaç dakika sonra. */
    fun nextStart(c: Config, wm: Int): Pair<Rule, Int>? {
        for (i in 1..WEEK) {
            val m = (wm + i) % WEEK
            val r = c.rules.firstOrNull { covers(it, m) && !covers(it, (m - 1 + WEEK) % WEEK) }
            if (r != null) return r to i
        }
        return null
    }

    /** Yeni ayar eskisinden daha sıkı (ya da aynı) mı? Öyleyse hemen uygulanabilir. */
    fun isStricterOrEqual(new: Config, old: Config): Boolean {
        // Her hedef için eski yasak dakikaları yenide de yasak olmalı
        val oldMasks = old.rules.map { it to mask(it) }
        val newMasks = new.rules.map { it to mask(it) }
        val targets = old.rules.flatMap { it.targets() }.toSet()
        for (t in targets) {
            val o = BitSet(WEEK)
            oldMasks.filter { t in it.first.targets() }.forEach { o.or(it.second) }
            val n = BitSet(WEEK)
            newMasks.filter { t in it.first.targets() }.forEach { n.or(it.second) }
            o.andNot(n)
            if (!o.isEmpty) return false
        }
        return true
    }

    // ---------- Biçimlendirme ----------

    fun fmt(m: Int): String = String.format("%02d:%02d", (m / 60) % 24, m % 60)

    fun fmtDuration(min: Int): String {
        val d = min / 1440
        val h = (min % 1440) / 60
        val m = min % 60
        val parts = mutableListOf<String>()
        if (d > 0) parts.add("$d gün")
        if (h > 0) parts.add("$h sa")
        if (m > 0 || parts.isEmpty()) parts.add("$m dk")
        return parts.joinToString(" ")
    }

    /** Haftanın dakikası -> "Sal 09:00" ya da bugünse "09:00" */
    fun fmtWeekMinute(wm: Int, nowWm: Int): String {
        val day = (wm / 1440) % 7
        val t = fmt(wm % 1440)
        return if (day == (nowWm / 1440) % 7) t else "${DAY_NAMES[day]} $t"
    }

    /** ms -> "15:00", "Yarın 15:00" ya da "Sal 15:00" */
    fun fmtMillis(ms: Long): String {
        val z = java.time.ZoneId.systemDefault()
        val t = java.time.Instant.ofEpochMilli(ms).atZone(z)
        val today = java.time.LocalDate.now(z)
        val hm = fmt(t.hour * 60 + t.minute)
        return when (t.toLocalDate()) {
            today -> hm
            today.plusDays(1) -> "Yarın $hm"
            else -> "${DAY_NAMES[t.dayOfWeek.value - 1]} $hm"
        }
    }

    fun sessionsToJson(list: List<Session>): String {
        val arr = JSONArray()
        for (x in list) {
            arr.put(JSONObject().put("start", x.start).put("end", x.end)
                .put("apps", JSONArray(x.apps.toList())).put("sites", JSONArray(x.sites.toList())))
        }
        return arr.toString()
    }

    fun sessionsFromJson(s: String?): List<Session> {
        if (s == null) return emptyList()
        return try {
            val arr = JSONArray(s)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                Session(o.getLong("start"), o.getLong("end"), strSet(o.optJSONArray("apps")), strSet(o.optJSONArray("sites")))
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    fun fmtRange(g: Range): String =
        if (g.start == g.end) "Tüm gün" else "${fmt(g.start)}–${fmt(g.end)}"

    fun fmtDays(days: List<Boolean>): String {
        val all = days.all { it }
        val weekday = (0..4).all { days[it] } && !days[5] && !days[6]
        val weekend = (0..4).none { days[it] } && days[5] && days[6]
        return when {
            all -> "Her gün"
            weekday -> "Hafta içi"
            weekend -> "Hafta sonu"
            days.none { it } -> "Gün seçilmedi"
            else -> (0 until 7).filter { days[it] }.joinToString(" ") { DAY_NAMES[it] }
        }
    }

    // ---------- Siteler ----------

    /** "https://www.YouTube.com/watch?v=..." -> "youtube.com" */
    fun normalizeHost(s: String): String {
        var x = s.trim().lowercase()
        x = x.substringAfter("://")
        x = x.substringBefore('/').substringBefore('?').substringBefore('#')
        x = x.substringAfter('@').substringBefore(':')
        x = x.trimEnd('.')
        if (x.startsWith("www.")) x = x.removePrefix("www.")
        return x
    }

    fun parseSites(text: String): Set<String> =
        text.lines().map { normalizeHost(it) }.filter { it.isNotEmpty() && !it.contains(' ') && it.contains('.') }.toSet()

    fun hostMatches(urlText: String, site: String): Boolean {
        val host = normalizeHost(urlText)
        if (host.isEmpty()) return false
        return host == site || host.endsWith(".$site")
    }

    // ---------- JSON ----------

    fun toJson(c: Config): String {
        val arr = JSONArray()
        for (r in c.rules) {
            val o = JSONObject()
            o.put("id", r.id)
            o.put("name", r.name)
            o.put("kind", r.kind)
            val d = JSONArray(); r.days.forEach { d.put(it) }; o.put("days", d)
            val g = JSONArray(); r.ranges.forEach { g.put(JSONArray().put(it.start).put(it.end)) }; o.put("ranges", g)
            o.put("apps", JSONArray(r.apps.toList()))
            o.put("sites", JSONArray(r.sites.toList()))
            arr.put(o)
        }
        return JSONObject().put("v", 2).put("rules", arr).toString()
    }

    private fun strSet(a: JSONArray?): Set<String> =
        if (a == null) emptySet() else (0 until a.length()).map { a.getString(it) }.toSet()

    private fun ranges(a: JSONArray?): List<Range> =
        if (a == null) emptyList() else (0 until a.length()).map { val x = a.getJSONArray(it); Range(x.getInt(0), x.getInt(1)) }

    fun fromJson(s: String?): Config? {
        if (s == null) return null
        return try {
            val o = JSONObject(s)
            if (o.has("rules")) {
                val arr = o.getJSONArray("rules")
                val rules = (0 until arr.length()).map { i ->
                    val r = arr.getJSONObject(i)
                    val d = r.optJSONArray("days")
                    val days = (0 until 7).map { k -> d == null || (k < d.length() && d.getBoolean(k)) }
                    Rule(
                        id = r.optString("id", newId()),
                        name = r.optString("name", "Kural"),
                        kind = r.optString("kind", KIND_RUTIN),
                        days = days,
                        ranges = ranges(r.optJSONArray("ranges")),
                        apps = strSet(r.optJSONArray("apps")),
                        sites = strSet(r.optJSONArray("sites"))
                    )
                }
                Config(rules)
            } else {
                // Eski sürümden geçiş: tek bir "Genel" rutin kural
                val rg = ranges(o.optJSONArray("ranges"))
                val apps = strSet(o.optJSONArray("apps"))
                val sites = strSet(o.optJSONArray("sites"))
                if (rg.isEmpty() && apps.isEmpty() && sites.isEmpty()) Config(emptyList())
                else Config(listOf(Rule(newId(), "Genel", KIND_RUTIN, List(7) { true }, rg.map { Range(it.start, it.end % 1440) }, apps, sites)))
            }
        } catch (e: Exception) {
            null
        }
    }
}
