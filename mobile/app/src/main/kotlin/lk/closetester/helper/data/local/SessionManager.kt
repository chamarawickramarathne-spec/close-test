package lk.closetester.helper.data.local

import android.util.Base64
import lk.closetester.helper.core.AppConfig
import lk.closetester.helper.data.api.SupabaseApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import retrofit2.HttpException
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SessionManager @Inject constructor(
    private val api: SupabaseApi,
    private val store: SessionStore
) {
    private val refreshLock = Mutex()

    suspend fun hasSession(): Boolean =
        store.session.first().accessToken?.isNotBlank() == true

    suspend fun accessToken(): String {
        val current = store.session.first().accessToken?.takeIf { it.isNotBlank() }
            ?: throw SessionExpiredException()
        if (!expiresSoon(current)) return current
        return refreshLocked()
    }

    suspend fun <T> withAuth(block: suspend (String) -> T): T {
        val token = accessToken()
        return try {
            block(token)
        } catch (e: HttpException) {
            if (e.code() != 401) throw e
            val renewed = refreshLocked(staleToken = token)
            try {
                block(renewed)
            } catch (retry: HttpException) {
                if (retry.code() != 401) throw retry
                store.clearSession()
                throw SessionExpiredException()
            }
        }
    }

    suspend fun signOut() {
        store.clearSession()
    }

    private suspend fun refreshLocked(staleToken: String? = null): String = refreshLock.withLock {
        val current = store.session.first()
        val access = current.accessToken?.takeIf { it.isNotBlank() }
        if (access != null && !expiresSoon(access) && (staleToken == null || access != staleToken)) {
            return@withLock access
        }

        val refresh = current.refreshToken?.takeIf { it.isNotBlank() } ?: run {
            store.clearSession()
            throw SessionExpiredException()
        }

        val renewed = try {
            api.refreshToken(AppConfig.SUPABASE_ANON_KEY, mapOf("refresh_token" to refresh))
        } catch (e: HttpException) {
            if (e.code() == 400 || e.code() == 401) {
                store.clearSession()
                throw SessionExpiredException()
            }
            throw e
        }

        val newAccess = renewed.accessToken?.takeIf { it.isNotBlank() } ?: run {
            store.clearSession()
            throw SessionExpiredException()
        }
        val newRefresh = renewed.refreshToken?.takeIf { it.isNotBlank() } ?: refresh
        store.replaceSession(newAccess, newRefresh)
        newAccess
    }

    private fun expiresSoon(token: String, skewMillis: Long = 60_000L): Boolean {
        val expSeconds = expirySeconds(token) ?: return false
        return expSeconds * 1000L <= System.currentTimeMillis() + skewMillis
    }

    private fun expirySeconds(token: String): Long? {
        val payload = token.split('.').getOrNull(1) ?: return null
        return try {
            val raw = Base64.decode(payload, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
            JSONObject(String(raw)).optLong("exp", 0L).takeIf { it > 0L }
        } catch (_: Exception) {
            null
        }
    }
}
