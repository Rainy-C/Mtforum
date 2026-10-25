package me.rain.mtforum.feature.home

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.*
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.rain.mtforum.core.network.*
import me.rain.mtforum.core.ui.*
import me.rain.mtforum.core.ui.icons.*
import me.rain.mtforum.feature.auth.LoginScreen
import me.rain.mtforum.feature.auth.VerificationHost
import me.rain.mtforum.feature.forum.*
import me.rain.mtforum.feature.profile.*
import me.rain.mtforum.feature.web.ForumBrowserScreen
import org.json.JSONObject
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.extra.SuperDialog
import top.yukonga.miuix.kmp.theme.MiuixTheme

private data class Route(val id: String, val kind: String, val title: String, val url: String = "")

private val routeSaver =
    listSaver<List<Route>, String>(
        save = { list ->
            list.map {
                JSONObject()
                    .put("id", it.id)
                    .put("kind", it.kind)
                    .put("title", it.title)
                    .put("url", it.url)
                    .toString()
            }
        },
        restore = { list ->
            list.map {
                JSONObject(it).let { o ->
                    Route(
                        o.getString("id"),
                        o.getString("kind"),
                        o.getString("title"),
                        o.getString("url"),
                    )
                }
            }
        },
    )

@Composable
fun HomeScreen(account: AccountViewModel = viewModel()) {
    var selected by rememberSaveable { mutableIntStateOf(0) }
    val state by account.state.collectAsStateWithLifecycle()
    val verification by account.repository.verification.pending.collectAsStateWithLifecycle()
    var stack by
        rememberSaveable(stateSaver = routeSaver) {
            mutableStateOf(listOf(Route("tabs", "tabs", "")))
        }
    val logout = remember { mutableStateOf(false) }
    val tabStates = rememberSaveableStateHolder()
    val routeStates = rememberSaveableStateHolder()
    val navigationScope = rememberCoroutineScope()
    // A mounted route remains the SAME composition when another route covers it.
    // Screenshots and re-created destination screens caused gesture-only reload flashes.
    val routeSlides = remember { linkedMapOf<String, Animatable<Float, androidx.compose.animation.core.AnimationVector1D>>() }
    val visitedTabs = remember { mutableStateListOf(0) }
    val refreshRequests = remember { mutableStateMapOf<String, Int>() }
    var navigating by remember { mutableStateOf(false) }
    LaunchedEffect(selected) {
        if (selected !in visitedTabs) visitedTabs.add(selected)
    }
    LaunchedEffect(stack.last().id) {
        delay(PageTransitionMillis.toLong())
        navigating = false
    }
    val context = LocalContext.current
    fun push(kind: String, title: String = "", url: String = "") {
        if (navigating) return
        navigating = true
        stack = stack + Route(java.util.UUID.randomUUID().toString(), kind, title, url)
    }
    fun commitBack() {
        if (stack.size <= 1) return
        val leavingWeb = stack.last().kind == "web"
        if (leavingWeb) account.syncBrowserSession()
        val closeLogin = leavingWeb && account.state.value.loggedIn &&
            stack.getOrNull(stack.lastIndex - 1)?.kind == "login"
        val count = if (closeLogin) 2 else 1
        val departing = stack.takeLast(count)
        stack = stack.dropLast(count)
        departing.forEach { routeSlides.remove(it.id) }
        navigating = false
    }
    fun back(gesture: Boolean = false) {
        if (stack.size <= 1 || navigating) return
        if (gesture) {
            commitBack()
        } else {
            val id = stack.last().id
            navigating = true
            navigationScope.launch {
                // Toolbar and edge-back both expose the already-mounted destination.
                val animation = routeSlides[id]
                if (animation != null) {
                    animation.animateTo(1f, tween(PageTransitionMillis, easing = FastOutSlowInEasing))
                }
                if (stack.lastOrNull()?.id == id) commitBack()
                navigating = false
            }
        }
    }
    fun login() {
        account.clearError()
        if (stack.last().kind != "login") push("login")
    }
    fun open(title: String, url: String) {
        if (url == "mtforum://account") {
            if (state.loggedIn) push("account") else login()
            return
        }
        val parsed = runCatching { Uri.parse(url) }.getOrNull() ?: return
        if (parsed.scheme != "https") return
        val image =
            title == "图片" ||
                Regex("""\.(?:png|jpe?g|gif|webp)(?:[?].*)?$""", RegexOption.IGNORE_CASE)
                    .containsMatchIn(url)
        if (image && parsed.host in ForumMedia.Hosts) {
            push("image", title, url)
            return
        }
        if (
            parsed.host == ForumRepository.Host &&
                (parsed.getQueryParameter("mod") == "attachment" ||
                    parsed.path.orEmpty().contains("attachment.php"))
        ) {
            push("download", title, url)
            return
        }
        if (parsed.host != ForumRepository.Host) {
            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, parsed)) }
            return
        }
        val path = parsed.path.orEmpty()
        val isPost = parsed.getQueryParameter("mod") == "post"
        val kind =
            when {
                parsed.getQueryParameter("action") == "login" -> "login"
                parsed.getQueryParameter("do") == "pm" &&
                    parsed.getQueryParameter("subop") == "view" &&
                    parsed.getQueryParameter("touid") != null -> "conversation"
                parsed.getQueryParameter("id") == "comiis_sms:comiis_setup" -> "sms"
                path.startsWith("/space-uid-") || path.startsWith("/space-username-") ||
                    parsed.getQueryParameter("mod") == "space" && parsed.getQueryParameter("uid") != null &&
                        parsed.getQueryParameter("do") in listOf(null, "profile") -> "user-space"
                ContentParser.topicId(url) != null &&
                    !isPost &&
                    !url.contains("nativeview=1") &&
                    (path.startsWith("/thread-") ||
                        parsed.getQueryParameter("mod") == "viewthread" ||
                        parsed.getQueryParameter("mod") == "redirect" &&
                            parsed.getQueryParameter("goto") == "findpost") -> "thread"
                ContentParser.forumId(url) != null &&
                    !isPost &&
                    (path.startsWith("/forum-") ||
                        parsed.getQueryParameter("mod") == "forumdisplay") -> "topics"
                else -> "native"
            }
        push(kind, title, url)
    }
    val items =
        listOf(
            NavigationItem("首页", MiuixNavigationIcons.Home),
            NavigationItem("社区", MiuixNavigationIcons.Community),
            NavigationItem("消息", MiuixNavigationIcons.Messages),
            NavigationItem("我的", MiuixNavigationIcons.Profile),
        )
    @Composable
    fun Render(route: Route) {
        when (route.kind) {
            "tabs" -> {
                var barHidden by remember { mutableStateOf(false) }
                val density = LocalDensity.current
                val directionThreshold = with(density) { 18.dp.toPx() }
                val scrollConnection = remember(directionThreshold, selected) {
                    object : NestedScrollConnection {
                        private var travel = 0f

                        override fun onPostScroll(
                            consumed: Offset,
                            available: Offset,
                            source: NestedScrollSource,
                        ): Offset {
                            // Observe only distance actually scrolled by the list. Overscroll
                            // and pull-to-refresh must not toggle the navigation bar.
                            val delta = consumed.y
                            if (delta == 0f) return Offset.Zero
                            if (travel * delta < 0f) travel = 0f
                            travel = (travel + delta).coerceIn(-directionThreshold, directionThreshold)
                            if (travel <= -directionThreshold) barHidden = true
                            if (travel >= directionThreshold) barHidden = false
                            return Offset.Zero
                        }
                    }
                }
                LaunchedEffect(selected) { barHidden = false }
                val barProgress by animateFloatAsState(
                    targetValue = if (barHidden) 1f else 0f,
                    animationSpec = tween(
                        durationMillis = if (barHidden) 260 else 300,
                        easing = FastOutSlowInEasing,
                    ),
                    label = "bottom-bar-collapse",
                )
                Box(Modifier.fillMaxSize()) {
                    // Keep visited tab compositions alive. In particular the community's
                    // fetched counters and scroll state must not reset on every tab switch.
                    val tabPosition by animateFloatAsState(
                        targetValue = selected.toFloat(),
                        animationSpec = tween(PageTransitionMillis, easing = FastOutSlowInEasing),
                        label = "main-tabs",
                    )
                    visitedTabs.forEach { page ->
                        key(page) {
                            Box(Modifier.fillMaxSize().graphicsLayer {
                                translationX = size.width * (page - tabPosition)
                            }.nestedScroll(scrollConnection)) {
                                tabStates.SaveableStateProvider(page) {
                            when (page) {
                                0 ->
                                    TopicsScreen(
                                        account.repository,
                                        "首页",
                                        "",
                                        home = true,
                                        sessionKey = state.loggedIn,
                                        onSearch = { push("search") },
                                        onOpen = ::open,
                                    )
                                1 -> CommunityScreen(account.repository, ::open)
                                2 ->
                                    MessagesScreen(
                                        state.loggedIn,
                                        account.repository,
                                        ::login,
                                        ::open,
                                    )
                                else ->
                                    ProfileScreen(
                                        state,
                                        ::login,
                                        account::refresh,
                                        { logout.value = true },
                                        ::open,
                                        { push("about") },
                                        { push("settings") },
                                        { push("avatar") },
                                    )
                                }
                            }
                        }
                    }
                    }
                    Box(
                        Modifier.align(Alignment.BottomCenter)
                            .graphicsLayer {
                                // Transform the inset together with the bar so it disappears
                                // below the physical screen, including gesture navigation.
                                translationY = size.height * barProgress
                                scaleX = 1f - 0.28f * barProgress
                                scaleY = 1f - 0.55f * barProgress
                                alpha = 1f - barProgress
                                // Keep shadow compositing consistent at the final animation frame.
                                compositingStrategy = CompositingStrategy.ModulateAlpha
                                transformOrigin = TransformOrigin(0.5f, 1f)
                            }
                            .navigationBarsPadding()
                            .padding(bottom = 14.dp)
                    ) {
                        FloatingNavigationBar(
                            items = items,
                            selected = selected,
                            onClick = {
                                if (it !in visitedTabs) visitedTabs.add(it)
                                selected = it
                            },
                            mode = FloatingNavigationBarMode.IconOnly,
                            modifier = Modifier.heightIn(min = 52.dp),
                            shadowElevation = 8.dp,
                            defaultWindowInsetsPadding = false,
                        )
                    }
                }
            }
            "login" ->
                LoginScreen(
                    state,
                    { back() },
                    {
                        push(
                            "web",
                            "登录论坛",
                            "${ForumRepository.BaseUrl}/member.php?mod=logging&action=login&mobile=2",
                        )
                    },
                    account::login,
                )
            "web" -> ForumBrowserScreen(route.title, route.url) { back() }
            "conversation" ->
                ConversationScreen(
                    account.repository,
                    Uri.parse(route.url).getQueryParameter("touid").orEmpty(),
                    route.title,
                    { back() },
                    ::open,
                )
            "sms" -> SmsScreen(account.repository, { back() })
            "user-space" -> UserSpaceScreen(account.repository, route.url, { back() }, ::open)
            "thread" ->
                ThreadScreen(
                    account.repository,
                    route.url,
                    { back() },
                    state.loggedIn,
                    ::login,
                    ::open,
                )
            "topics" ->
                TopicsScreen(
                    account.repository,
                    route.title,
                    route.url,
                    sessionKey = state.loggedIn,
                    onBack = { back() },
                    onSearch = { push("search") },
                    onCompose = {
                        if (!state.loggedIn) login()
                        else
                            open(
                                "发布帖子",
                                "${ForumRepository.BaseUrl}/forum.php?mod=post&action=newthread&fid=${ContentParser.forumId(route.url)}&mobile=2",
                            )
                    },
                    onOpen = ::open,
                )
            "native" ->
                NativePageScreen(
                    account.repository,
                    route.title,
                    route.url,
                    { back() },
                    onOpen = ::open,
                    onChanged = {
                        account.refresh()
                        // A successful mutation refreshes its parent in the background.
                        // Ordinary navigation/back does not trigger any page reload.
                        val parent = stack.getOrNull(stack.lastIndex - 1)
                        if (parent?.kind == "native") {
                            refreshRequests[parent.id] = (refreshRequests[parent.id] ?: 0) + 1
                        }
                    },
                    reloadToken = refreshRequests[route.id] ?: 0,
                    onLogin = ::login,
                )
            "image",
            "download" ->
                MediaScreen(
                    account.repository,
                    route.title,
                    route.url,
                    route.kind == "image",
                    { back() },
                )
            "search" -> SearchScreen(account.repository, { back() }, ::open)
            "about" -> AboutScreen { back() }
            "account" -> AccountToolsScreen({ back() }, ::open)
            "settings" -> SettingsScreen({ back() }, { push("about") })
            "avatar" ->
                AvatarScreen(
                    account.repository,
                    state.profile?.avatarUrl,
                    { back() },
                    account::refresh,
                )
        }
    }
    Box(Modifier.fillMaxSize().clipToBounds().background(MiuixTheme.colorScheme.background)) {
        Render(stack.first())
        // Every open detail route owns a stable keyed composition, regardless of whether
        // it is active or covered. Neither a tab switch nor a nested navigation can
        // destroy the destination that edge-back reveals.
        stack.drop(1).forEachIndexed { index, route ->
            key(route.id) {
                val isTop = index == stack.size - 2
                val slide = remember(route.id) {
                    routeSlides.getOrPut(route.id) { Animatable(1f) }
                }
                LaunchedEffect(route.id) {
                    slide.animateTo(0f, tween(PageTransitionMillis, easing = FastOutSlowInEasing))
                }
                Box(Modifier.fillMaxSize().graphicsLayer {
                    // Retain older routes in composition without redrawing every
                    // fullscreen page behind the top two layers each frame.
                    alpha = if (index >= stack.size - 3) 1f else 0f
                    translationX = size.width * slide.value
                }) {
                    SwipeBackScene(
                        enabled = isTop && !navigating && !state.signingIn && verification == null,
                        onBack = { back(true) },
                        // The actual previous page is already composed immediately below.
                        // An empty reveal layer avoids any screenshot-to-live swap.
                        previous = {},
                    ) {
                        Box(Modifier.fillMaxSize().background(MiuixTheme.colorScheme.background)) {
                            routeStates.SaveableStateProvider(route.id) { Render(route) }
                        }
                    }
                }
            }
        }
        SuperDialog(
            show = logout,
            title = "退出登录",
            summary = "确定退出当前账号？",
            onDismissRequest = { logout.value = false },
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ActionButton("取消", Modifier.weight(1f), primary = false) { logout.value = false }
                ActionButton("退出登录", Modifier.weight(1f)) {
                    logout.value = false
                    account.logout()
                }
            }
        }
        verification?.let { VerificationHost(it, account.repository) }
        AutoUpdateCheck()
    }
}

@Composable
private fun MessagesScreen(
    loggedIn: Boolean,
    repository: ForumRepository,
    onLogin: () -> Unit,
    onOpen: (String, String) -> Unit,
) {
    var category by rememberSaveable { mutableIntStateOf(0) }
    val paths = listOf("do=pm", "do=notice&view=mypost&type=post", "do=notice&view=system")
    Column(Modifier.fillMaxSize()) {
        PageHeader("消息")
        if (!loggedIn)
            Box(Modifier.fillMaxSize(), Alignment.Center) {
                EmptyState(
                    "登录后查看消息",
                    icon = MiuixNavigationIcons.Messages,
                    action = "登录论坛",
                    onAction = onLogin,
                )
            }
        else {
            FilterBar(listOf("私信", "提醒", "系统"), category) { category = it }
            if (category == 0) ConversationList(repository, onOpen)
            else
                NativePageScreen(
                    repository,
                    "消息",
                    "${ForumRepository.BaseUrl}/home.php?mod=space&${paths[category]}&mobile=2",
                    bottomInset = true,
                    onOpen = onOpen,
                    showHeader = false,
                    onLogin = onLogin,
                )
        }
    }
}
