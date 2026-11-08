package lk.closetester.helper.core

object PlayLink {
    private const val HOST = "play.google.com"
    private val PACKAGE = Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$")

    fun isValid(raw: String?): Boolean {
        val text = raw?.trim().orEmpty()
        if (text.isEmpty() || text.length > 500) return false
        val uri = runCatching { java.net.URI(text) }.getOrNull() ?: return false
        if (!uri.scheme.equals("https", ignoreCase = true)) return false
        if (!uri.host.equals(HOST, ignoreCase = true)) return false
        if (uri.userInfo != null) return false
        if (uri.port != -1 && uri.port != 443) return false
        val path = uri.path.orEmpty()
        if (path.startsWith("/apps/testing/")) {
            return PACKAGE.matches(path.removePrefix("/apps/testing/").trimEnd('/'))
        }
        if (path == "/store/apps/details") {
            val id = uri.query.orEmpty()
                .split('&')
                .firstOrNull { it.startsWith("id=") }
                ?.substringAfter("id=")
                ?: return false
            return PACKAGE.matches(id)
        }
        return false
    }
}
