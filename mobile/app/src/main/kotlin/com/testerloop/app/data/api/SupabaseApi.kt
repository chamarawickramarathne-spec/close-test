package com.testerloop.app.data.api

import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.PUT

interface SupabaseApi {
    @POST("/auth/v1/token?grant_type=password")
    suspend fun signIn(@Header("apikey") apiKey: String, @Body req: AuthRequest): AuthResponse

    @POST("/auth/v1/signup")
    suspend fun signUp(@Header("apikey") apiKey: String, @Body req: AuthRequest): AuthResponse

    @POST("/auth/v1/token?grant_type=refresh_token")
    suspend fun refreshToken(@Header("apikey") apiKey: String, @Body body: Map<String, String>): AuthResponse

    @POST("/auth/v1/recover")
    suspend fun recover(@Header("apikey") apiKey: String, @Body body: Map<String, String>): Response<Unit>

    @POST("/auth/v1/verify")
    suspend fun verifyRecovery(@Header("apikey") apiKey: String, @Body body: Map<String, String>): AuthResponse

    @PUT("/auth/v1/user")
    suspend fun updatePassword(
        @Header("apikey") apiKey: String,
        @Header("Authorization") auth: String,
        @Body body: Map<String, String>
    ): Response<Unit>

    @POST("/rest/v1/rpc/whoami")
    suspend fun whoami(@Header("apikey") apiKey: String, @Header("Authorization") auth: String): Map<String, Any>

    @POST("/rest/v1/rpc/claim_profile")
    suspend fun claimProfile(@Header("apikey") apiKey: String, @Header("Authorization") auth: String): Response<Unit>

    @POST("/rest/v1/rpc/ensure_account_role")
    suspend fun ensureAccountRole(
        @Header("apikey") apiKey: String,
        @Header("Authorization") auth: String,
        @Body req: EnsureRoleRequest
    ): Response<Unit>

    @POST("/rest/v1/rpc/tester_dashboard")
    suspend fun testerDashboard(@Header("apikey") apiKey: String, @Header("Authorization") auth: String): TesterDashboard

    @POST("/rest/v1/rpc/join_campaign")
    suspend fun joinCampaign(
        @Header("apikey") apiKey: String,
        @Header("Authorization") auth: String,
        @Body body: Map<String, String>
    ): Response<Unit>

    @POST("/rest/v1/rpc/set_opt_in")
    suspend fun setOptIn(
        @Header("apikey") apiKey: String,
        @Header("Authorization") auth: String,
        @Body req: SetOptInRequest
    ): Response<Unit>

    @POST("/functions/v1/verify-opt-in")
    suspend fun verifyOptIn(
        @Header("apikey") apiKey: String,
        @Header("Authorization") auth: String,
        @Body body: Map<String, String>
    ): Map<String, Any>

    @POST("/rest/v1/rpc/report_app_install_daily")
    suspend fun reportAppInstallDaily(
        @Header("apikey") apiKey: String,
        @Header("Authorization") auth: String,
        @Body req: ReportInstallRequest
    ): Response<Unit>

    @POST("/rest/v1/rpc/report_app_usage_daily")
    suspend fun reportAppUsageDaily(
        @Header("apikey") apiKey: String,
        @Header("Authorization") auth: String,
        @Body req: RpcRequest
    ): Response<Unit>

    @POST("/rest/v1/rpc/record_tester_device")
    suspend fun recordTesterDevice(
        @Header("apikey") apiKey: String,
        @Header("Authorization") auth: String,
        @Body req: RecordDeviceRequest
    ): Response<Unit>

    @POST("/rest/v1/rpc/update_tester_profile")
    suspend fun updateTesterProfile(
        @Header("apikey") apiKey: String,
        @Header("Authorization") auth: String,
        @Body req: UpdateProfileRequest
    ): Response<Unit>

    @POST("/rest/v1/rpc/file_report")
    suspend fun fileReport(
        @Header("apikey") apiKey: String,
        @Header("Authorization") auth: String,
        @Body req: FileReportRequest
    ): Response<Unit>
}
