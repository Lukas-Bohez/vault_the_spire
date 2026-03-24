package com.example.vault_the_spire

import android.app.Service
import android.content.Intent
import android.os.IBinder

class TorrentForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // No-op fallback service. Specific torrent engine implementation should manage
        // notifications and foreground life cycle.
        return START_STICKY
    }
}
