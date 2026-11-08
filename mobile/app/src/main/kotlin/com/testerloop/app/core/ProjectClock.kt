package com.testerloop.app.core

import com.testerloop.app.data.api.MineItem

const val ClockDays = 14

data class ProjectClock(
    val days: Int,
    val requiredDays: Int,
    val confirmedTesters: Int,
    val requiredTesters: Int,
    val started: Boolean
) {
    val waitingFor: Int get() = (requiredTesters - confirmedTesters).coerceAtLeast(0)
    val progress: Float get() = (days.toFloat() / requiredDays).coerceIn(0f, 1f)
    val daysLabel: String get() = "$days of $requiredDays days"
    val waitingLabel: String get() =
        if (waitingFor == 1) "Waiting for 1 more confirmed tester"
        else "Waiting for $waitingFor more confirmed testers"
    val confirmedLabel: String get() = "$confirmedTesters of $requiredTesters confirmed"
}

fun MineItem.projectClock(): ProjectClock {
    val required = if (requiredTesters > 0) requiredTesters else 12
    val confirmed = confirmedTesters
    val started = when {
        clockStartedAt != null -> true
        confirmed != null -> confirmed >= required
        else -> true
    }
    return ProjectClock(
        days = if (started) days.coerceAtLeast(0) else 0,
        requiredDays = ClockDays,
        confirmedTesters = confirmed ?: required,
        requiredTesters = required,
        started = started
    )
}
