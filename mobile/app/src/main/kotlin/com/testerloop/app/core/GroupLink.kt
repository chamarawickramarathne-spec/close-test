package com.testerloop.app.core

object GroupLink {
    private val SLUG = Regex("^[a-z0-9](?:[a-z0-9._-]{0,198}[a-z0-9])?$")

    fun url(name: String?): String? {
        val slug = name?.trim()?.lowercase().orEmpty()
        if (slug.isEmpty() || !SLUG.matches(slug)) return null
        return "https://groups.google.com/g/$slug"
    }
}
