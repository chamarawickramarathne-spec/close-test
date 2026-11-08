package com.testerloop.app.core

object AppConfig {
    const val SUPABASE_URL = "https://omlhddzyitzjbcgrxvbn.supabase.co"
    const val SUPABASE_ANON_KEY = "sb_publishable_muvojumpOQ52sZirZKA4Lw_6BcNVb8G"
    const val DASHBOARD_REFRESH_MS = 60_000L

    const val GITHUB_OWNER = "chamarawickramarathne-spec"
    const val GITHUB_REPO = "close-test"
    const val UPDATE_CHECK_URL = "https://api.github.com/repos/chamarawickramarathne-spec/close-test/releases/latest"
    const val UPDATE_MANIFEST_URL =
        "https://github.com/chamarawickramarathne-spec/close-test/releases/latest/download/mobile-version.json"
    const val UPDATE_DOWNLOAD_BASE =
        "https://github.com/chamarawickramarathne-spec/close-test/releases/latest/download/"
}
