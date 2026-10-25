package me.rain.mtforum.core.network

import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.Assert.*
import org.junit.Test

class VerificationCoordinatorTest {
    @Test fun verificationRequestsAreSerializedAndRequireExplicitResults() = runBlocking {
        val gate = VerificationCoordinator()
        val first = async(start = CoroutineStart.UNDISPATCHED) { gate.verify("first") }
        val firstRequest = checkNotNull(gate.pending.value)
        val second = async(start = CoroutineStart.UNDISPATCHED) { gate.verify("second") }
        assertEquals(firstRequest.id, gate.pending.value?.id)
        firstRequest.result.complete(true)
        assertTrue(first.await())
        withTimeout(1000) { while (gate.pending.value?.url != "second") yield() }
        val secondRequest = checkNotNull(gate.pending.value)
        assertTrue(secondRequest.id > firstRequest.id)
        secondRequest.result.complete(false)
        assertFalse(second.await())
        assertNull(gate.pending.value)
    }

    @Test fun cancellingCallerRemovesPendingVerification() = runBlocking {
        val gate = VerificationCoordinator()
        val request = async(start = CoroutineStart.UNDISPATCHED) { gate.verify("cancel") }
        assertNotNull(gate.pending.value)
        request.cancelAndJoin()
        assertNull(gate.pending.value)
    }
}
