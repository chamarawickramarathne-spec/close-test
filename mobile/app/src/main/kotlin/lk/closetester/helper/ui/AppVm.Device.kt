package lk.closetester.helper.ui

import lk.closetester.helper.core.AppConfig
import lk.closetester.helper.core.DeviceInfo
import lk.closetester.helper.data.api.RecordDeviceRequest
import lk.closetester.helper.data.api.apiMessage
import lk.closetester.helper.data.api.orThrow
import lk.closetester.helper.data.local.SessionExpiredException
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
