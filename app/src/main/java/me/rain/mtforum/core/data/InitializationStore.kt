package me.rain.mtforum.core.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.initializationDataStore by preferencesDataStore(name = "initialization")

class InitializationStore(context: Context) {
    private val dataStore = context.applicationContext.initializationDataStore

    /** A persisted consent is enough to enter the app without waiting for the network.
     * The document digest is checked separately when a fresh note is available.
     */
    fun acceptedDigest(): Flow<String?> = dataStore.data.map { preferences ->
        if (preferences[AcceptedAgreementVersion] == AgreementVersion) {
            preferences[AcceptedAgreementDigest]
        } else null
    }

    /** A revised remotely hosted document needs new consent, not just a new app version. */
    fun isCompleteFor(agreementDigest: String): Flow<Boolean> = dataStore.data.map { preferences ->
        preferences[AcceptedAgreementVersion] == AgreementVersion &&
            preferences[AcceptedAgreementDigest] == agreementDigest
    }

    suspend fun complete(agreementDigest: String) {
        dataStore.edit { preferences ->
            preferences[AcceptedAgreementVersion] = AgreementVersion
            preferences[AcceptedAgreementDigest] = agreementDigest
        }
    }

    private companion object {
        const val AgreementVersion = 3
        val AcceptedAgreementVersion = intPreferencesKey("accepted_agreement_version")
        val AcceptedAgreementDigest = stringPreferencesKey("accepted_agreement_digest")
    }
}
