package me.rain.mtforum.core.network

/** The guide categories are independent endpoints, not backend combinable query parameters. */
internal object GuideFeeds {
    val titles = listOf("热门", "最新", "精华", "抢沙发")
    val views = listOf("hot", "newthread", "digest", "sofa")

    fun selected(mask: Int): List<String> = views.filterIndexed { index, _ -> mask and (1 shl index) != 0 }

    fun toggle(mask: Int, index: Int): Int {
        val changed = mask xor (1 shl index)
        return if (changed == 0) mask else changed // Always keep at least one feed.
    }

    fun merge(selected: List<String>, pages: Map<String, GuideFeedPage>): List<Topic> {
        val lists = selected.map { pages[it]?.topics.orEmpty() }
        val result = ArrayList<Topic>()
        val seen = HashSet<String>()
        for (index in 0 until (lists.maxOfOrNull { it.size } ?: 0)) {
            for (topics in lists) {
                val topic = topics.getOrNull(index) ?: continue
                if (seen.add(topic.id)) result.add(topic)
            }
        }
        return result
    }
}

internal data class GuideFeedPage(
    val topics: List<Topic>,
    val next: String?,
    val generation: Int,
)
