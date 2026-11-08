package com.testerloop.app.data.api

import org.json.JSONObject
import retrofit2.HttpException
import retrofit2.Response

fun apiMessage(e: Throwable): String {
    if (e is HttpException) {
        val body = try {
            e.response()?.errorBody()?.string()
        } catch (_: Exception) {
            null
        }
        if (!body.isNullOrBlank()) {
            try {
                val json = JSONObject(body)
                for (key in listOf("msg", "message", "error_description", "error", "hint")) {
                    val value = json.optString(key)
                    if (value.isNotBlank()) return value
                }
            } catch (_: Exception) {
                return body
            }
        }
        if (e.code() == 401) return "Your session expired. Sign in again."
        if (e.code() == 404) return "This feature is not available on the server yet."
        return "Request failed (${e.code()}). Try again."
    }
    return e.message?.takeIf { it.isNotBlank() } ?: "Something went wrong. Try again."
}

fun <T> Response<T>.orThrow(): Response<T> {
    if (!isSuccessful) throw HttpException(this)
    return this
}
