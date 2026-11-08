package com.testerloop.app.core

import java.text.ParseException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

fun initialsOf(name: String?, fallback: String = "TL"): String {
    val parts = name.orEmpty().trim().split(Regex("\\s+")).filter { it.isNotBlank() }
    if (parts.isEmpty()) return fallback
    return when {
        parts.size == 1 -> parts[0].take(2).uppercase(Locale.US)
        else -> (parts.first().take(1) + parts.last().take(1)).uppercase(Locale.US)
    }
}

fun firstNameOf(name: String?): String =
    name.orEmpty().trim().split(Regex("\\s+")).firstOrNull().orEmpty()

fun formatDate(iso: String?): String {
    if (iso.isNullOrBlank()) return "—"
    val formats = listOf(
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'",
        "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "yyyy-MM-dd'T'HH:mm:ssXXX",
        "yyyy-MM-dd"
    )
    for (pattern in formats) {
        try {
            val parser = SimpleDateFormat(pattern, Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
                isLenient = false
            }
            val date = parser.parse(iso) ?: continue
            return SimpleDateFormat("d MMM yyyy", Locale.US).format(date)
        } catch (_: ParseException) {
            continue
        }
    }
    return iso.take(10)
}

fun humanState(state: String?): String = when (state?.lowercase()) {
    "pending" -> "Pending"
    "awaiting_link" -> "Awaiting link"
    "live" -> "Live"
    "at_risk" -> "At risk"
    "passed" -> "Passed"
    "cancelled" -> "Cancelled"
    "opted_in" -> "Opted in"
    "joined" -> "Joined"
    "dropped" -> "Dropped"
    else -> state?.replace('_', ' ')?.replaceFirstChar { it.uppercase() } ?: "Unknown"
}

fun severityLabel(value: String?): String = when (value?.lowercase()) {
    "low", "minor" -> "Low"
    "medium", "normal" -> "Medium"
    "high", "major" -> "High"
    "critical", "blocker" -> "Critical"
    else -> value?.replaceFirstChar { it.uppercase() } ?: "Medium"
}

fun usageMinutes(ms: Long): String {
    val minutes = ms / 60_000L
    if (minutes < 60) return "${minutes}m"
    val hours = minutes / 60
    val rest = minutes % 60
    return if (rest == 0L) "${hours}h" else "${hours}h ${rest}m"
}
