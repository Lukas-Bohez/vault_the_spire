package com.torrentspire.ai

import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import id.flutter.flutter_background_service.BackgroundService

class MainActivity : FlutterActivity() {
	override fun onCreate(savedInstanceState: android.os.Bundle?) {
		getSharedPreferences("id.flutter.background_service", Context.MODE_PRIVATE)
			.edit()
			.putBoolean("is_manually_stopped", true)
			.putBoolean("is_foreground", false)
			.putBoolean("auto_start_on_boot", false)
			.apply()

		stopService(Intent(this, BackgroundService::class.java))
		super.onCreate(savedInstanceState)
	}
}
