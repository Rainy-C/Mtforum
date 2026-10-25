package me.rain.mtforum.feature.profile

import android.app.Application
import android.webkit.CookieManager
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import me.rain.mtforum.core.network.ForumCookies
import me.rain.mtforum.core.network.ForumException
import me.rain.mtforum.core.network.ForumProfile
import me.rain.mtforum.core.network.ForumRepository
import me.rain.mtforum.core.network.SessionExpiredException
import me.rain.mtforum.core.network.VerificationCoordinator

/** Account state survives tab switches and configuration changes. Passwords do not persist. */
class AccountViewModel(application: Application) : AndroidViewModel(application) {
    data class State(
        val loggedIn: Boolean = false,
        val profile: ForumProfile? = null,
        val loading: Boolean = false,
        val signingIn: Boolean = false,
        val error: String? = null,
    )

    private val cookies = ForumCookies(CookieManager.getInstance().apply { setAcceptCookie(true) })
    val repository = ForumRepository(cookies, VerificationCoordinator())
    private val mutableState = MutableStateFlow(State(loggedIn = cookies.hasSession()))
    val state = mutableState.asStateFlow()
    private var refreshJob: Job? = null
    private var logoutJob: Job? = null
    private var refreshGeneration = 0

    init {
        if (mutableState.value.loggedIn) refresh()
    }

    fun clearError() {
        mutableState.value = mutableState.value.copy(error = null)
    }

    fun login(
        username: String,
        password: String,
        question: Int,
        answer: String,
        onSuccess: () -> Unit,
    ) {
        if (mutableState.value.signingIn || mutableState.value.loading) return
        if (username.isBlank() || password.isEmpty() || (question != 0 && answer.isBlank())) {
            mutableState.value = mutableState.value.copy(error = "请填写账号、密码及所选安全问题的答案")
            return
        }
        viewModelScope.launch {
            mutableState.value = State(signingIn = true)
            try {
                repository.login(username.trim(), password, question, answer.trim())
                mutableState.value = State(loggedIn = true)
                onSuccess()
                refresh()
            } catch (error: CancellationException) {
                throw error
            } catch (error: IOException) {
                cookies.clearCore()
                mutableState.value = State(error = userMessage(error))
            } finally {
                mutableState.value = mutableState.value.copy(signingIn = false)
            }
        }
    }

    fun refresh() {
        if (mutableState.value.loading || mutableState.value.signingIn || !cookies.hasSession())
            return
        val generation = ++refreshGeneration
        refreshJob =
            viewModelScope.launch {
                mutableState.value =
                    mutableState.value.copy(loading = true, error = null, loggedIn = true)
                try {
                    val profile = repository.profile()
                    if (generation == refreshGeneration)
                        mutableState.value = mutableState.value.copy(profile = profile)
                } catch (error: SessionExpiredException) {
                    if (generation == refreshGeneration) {
                        cookies.clear()
                        mutableState.value = State(error = error.message)
                    }
                } catch (error: IOException) {
                    if (generation == refreshGeneration)
                        mutableState.value = mutableState.value.copy(error = userMessage(error))
                } finally {
                    if (generation == refreshGeneration)
                        mutableState.value = mutableState.value.copy(loading = false)
                }
            }
    }

    fun syncBrowserSession() {
        repository.clearContentCache()
        refreshGeneration++
        refreshJob?.cancel()
        refreshJob = null
        val loggedIn = cookies.hasSession()
        mutableState.value = State(loggedIn = loggedIn)
        if (loggedIn) {
            cookies.flush()
            refresh()
        }
    }

    fun logout() {
        if (mutableState.value.signingIn || logoutJob?.isActive == true) return
        refreshGeneration++
        refreshJob?.cancel()
        refreshJob = null
        logoutJob =
            viewModelScope.launch {
                mutableState.value = mutableState.value.copy(loading = true, error = null)
                try {
                    repository.logout()
                } finally {
                    mutableState.value = State()
                }
            }
    }

    private fun userMessage(error: IOException): String =
        if (error is ForumException) error.message ?: "论坛请求失败" else "暂时无法连接论坛，请检查网络后重试"
}
