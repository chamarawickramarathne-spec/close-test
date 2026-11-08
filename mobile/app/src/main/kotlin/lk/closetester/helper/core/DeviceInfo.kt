package lk.closetester.helper.core

import android.os.Build

object DeviceInfo {
    fun label(): String {
        val manufacturer = Build.MANUFACTURER.orEmpty().trim()
        val model = Build.MODEL.orEmpty().trim()

        val combined = when {
            model.isBlank() && manufacturer.isBlank() -> "Android device"
            model.isBlank() -> manufacturer
            manufacturer.isBlank() -> model
            model.startsWith(manufacturer, ignoreCase = true) -> model
            else -> "$manufacturer $model"
        }

        return combined
            .replace(Regex("\\s+"), " ")
            .take(120)
            .ifBlank { "Android device" }
    }
}
