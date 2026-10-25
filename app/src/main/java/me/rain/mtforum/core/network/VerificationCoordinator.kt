package me.rain.mtforum.core.network

import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull

class VerificationCoordinator {
    data class Request(val id: Long, val url: String, val result: CompletableDeferred<Boolean>)
    private val serial = Mutex()
    private val ids = AtomicLong()
    private val mutablePending = MutableStateFlow<Request?>(null)
    val pending = mutablePending.asStateFlow()

    suspend fun verify(url: String): Boolean = serial.withLock {
        val request = Request(ids.incrementAndGet(), url, CompletableDeferred())
        mutablePending.value = request
        try {
            withTimeoutOrNull(60_000) { request.result.await() } ?: false
        } finally {
            mutablePending.value = null
            request.result.cancel()
        }
    }
}
