package com.testerloop.app.ui

import androidx.lifecycle.viewModelScope
import com.testerloop.app.core.AppUpdater
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

fun AppVm.checkForUpdate(silent: Boolean = false) {
    if (ui.value.updateChecking || ui.value.updateDownloading) return
    updateState {
        it.copy(updateChecking = true, updateError = null, updateNotice = null)
    }
    viewModelScope.launch {
        try {
            val update = withContext(Dispatchers.IO) { AppUpdater.check() }
            updateState {
                it.copy(
                    updateChecking = false,
                    updateChecked = true,
                    updateAvailable = update,
                    updateNotice = if (update == null && !silent) {
                        "TesterLoop is up to date."
                    } else {
                        null
                    }
                )
            }
            if (update != null && silent) {
                message("TesterLoop ${update.versionName} is available. Open Profile to update.")
            }
        } catch (e: Exception) {
            updateState {
                it.copy(
                    updateChecking = false,
                    updateChecked = true,
                    updateError = if (silent) null else (e.message ?: "Could not reach the update server.")
                )
            }
        }
    }
}

fun AppVm.downloadAndInstallUpdate() {
    val update = ui.value.updateAvailable ?: return
    if (ui.value.updateDownloading) return
    if (!AppUpdater.canInstall(appContext)) {
        updateState {
            it.copy(
                updateError = null,
                updateNotice = "Allow installs from TesterLoop, then press Download and install again."
            )
        }
        sendEvent(UiEvent.OpenInstallPermission)
        return
    }
    updateState {
        it.copy(
            updateDownloading = true,
            updateProgress = 0,
            updateError = null,
            updateNotice = null
        )
    }
    viewModelScope.launch {
        try {
            val apk = withContext(Dispatchers.IO) {
                AppUpdater.download(appContext, update) { percent ->
                    updateState { it.copy(updateProgress = percent) }
                }
            }
            updateState {
                it.copy(
                    updateDownloading = false,
                    updateProgress = 100,
                    updateNotice = "Opening the installer for version ${update.versionName}."
                )
            }
            AppUpdater.install(appContext, apk)
        } catch (e: Exception) {
            updateState {
                it.copy(
                    updateDownloading = false,
                    updateError = e.message ?: "The update download failed."
                )
            }
        }
    }
}
