package lk.closetester.helper.data.local

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private val Context.dataStore by preferencesDataStore("testerloop")

@Singleton
class SessionStore @Inject constructor(@ApplicationContext private val context: Context) {
    private val accessToken = stringPreferencesKey("access_token")
    private val refreshToken = stringPreferencesKey("refresh_token")
    private val lastEmail = stringPreferencesKey("last_email")

    val session = context.dataStore.data.map { prefs ->
        Session(
            accessToken = prefs[accessToken],
            refreshToken = prefs[refreshToken]
        )
    }

    val lastEmailFlow = context.dataStore.data.map { prefs -> prefs[lastEmail] ?: "" }

    suspend fun replaceSession(access: String, refresh: String) {
        context.dataStore.edit { prefs ->
            prefs[accessToken] = access
            prefs[refreshToken] = refresh
        }
    }

    suspend fun saveLastEmail(email: String) {
        if (email.isNotBlank()) {
            context.dataStore.edit { prefs -> prefs[lastEmail] = email.trim() }
        }
    }

    suspend fun clearSession() {
        context.dataStore.edit { prefs ->
            prefs.remove(accessToken)
            prefs.remove(refreshToken)
        }
    }

    suspend fun clear() {
        context.dataStore.edit { it.clear() }
    }
}

data class Session(
    val accessToken: String? = null,
    val refreshToken: String? = null
)
