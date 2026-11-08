package com.testerloop.app.ui

import com.testerloop.app.core.AppConfig
import com.testerloop.app.core.DeviceInfo
import com.testerloop.app.data.api.RecordDeviceRequest
import com.testerloop.app.data.api.apiMessage
import com.testerloop.app.data.api.orThrow
import com.testerloop.app.data.local.SessionExpiredException
import retrofit2.HttpException

internal suspend fun AppVm.syncMobileDevice() {
    val device = DeviceInfo.label()
    try {
        session.withAuth { token ->
            api.recordTesterDevice(
                AppConfig.SUPABASE_ANON_KEY,
                "Bearer $token",
                RecordDeviceRequest(device)
            ).orThrow()
        }
        updateState {
            it.copy(
                tester = it.tester?.copy(mobileDeviceName = device),
                deviceError = null
            )
        }
    } catch (e: SessionExpiredException) {
        handleActionError(e)
    } catch (e: Exception) {
        updateState {
            it.copy(
                deviceError = if (e is HttpException && e.code() == 404) {
                    "Device reporting is not deployed yet. Ask operations to finish the mobile update."
                } else {
                    apiMessage(e)
                }
            )
        }
    }
}
