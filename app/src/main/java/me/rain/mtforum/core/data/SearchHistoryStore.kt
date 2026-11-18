package me.rain.mtforum.core.data

import android.content.Context
import org.json.JSONArray

/** Search keywords stay on this device; no history is uploaded by the app. */
object SearchHistoryStore {
    private const val FILE = "mtforum_search_history"
    private const val KEY = "recent_queries"

    fun load(context: Context): List<String> {
        val raw = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getString(KEY, "[]").orEmpty()
        return runCatching {
            val array = JSONArray(raw)
            val result = mutableListOf<String>()
            for (index in 0 until array.length()) {
                array.optString(index).takeIf(String::isNotBlank)?.let(result::add)
            }
            SearchHistoryPolicy.sanitize(result)
        }.getOrDefault(emptyList())
    }

    fun record(context: Context, keyword: String): List<String> {
        val updated = SearchHistoryPolicy.record(load(context), keyword)
        save(context, updated)
        return updated
    }

    fun remove(context: Context, keyword: String): List<String> {
        val updated = load(context).filterNot { it.equals(keyword, ignoreCase = true) }
        save(context, updated)
        return updated
    }

    fun clear(context: Context) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
            .remove(KEY).apply()
    }

    private fun save(context: Context, values: List<String>) {
        val array = JSONArray()
        values.forEach(array::put)
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
            .putString(KEY, array.toString()).apply()
    }
}

/** Pure history ordering/deduplication rules suitable for JVM tests. */
internal object SearchHistoryPolicy {
    const val MAX_ITEMS = 20
    private const val MAX_QUERY_CHARS = 100

    fun sanitize(values: List<String>): List<String> =
        values.asSequence()
            .map { it.trim().take(MAX_QUERY_CHARS) }
            .filter { it.isNotEmpty() }
            .distinctBy { it.lowercase() }
            .take(MAX_ITEMS)
            .toList()

    fun record(previous: List<String>, keyword: String): List<String> {
        val entry = keyword.trim().take(MAX_QUERY_CHARS)
        if (entry.isEmpty()) return sanitize(previous)
        return sanitize(listOf(entry) + previous)
    }
}
