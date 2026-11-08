package com.testerloop.app.core

val ACTIVE_CAMPAIGN_STATES = setOf("live", "at_risk")

fun isActiveCampaign(state: String?): Boolean =
    state?.trim()?.lowercase() in ACTIVE_CAMPAIGN_STATES
