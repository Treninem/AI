package com.aurorafox.runtime

import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.IBinder
import android.os.Process

class SandboxIsolatedService : Service() {
    inner class LocalBinder : Binder() {
        fun isActuallyIsolated(): Boolean = Process.isIsolated()
    }

    private val binder = LocalBinder()

    override fun onBind(intent: Intent?): IBinder = binder
}
