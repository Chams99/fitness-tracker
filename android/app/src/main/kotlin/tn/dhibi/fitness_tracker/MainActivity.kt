package tn.dhibi.fitness_tracker

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var updates: AndroidUpdateInstaller? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        updates = AndroidUpdateInstaller(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        updates?.close()
        updates = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onPostResume() {
        super.onPostResume()
        updates?.onResume()
    }

    override fun onPause() {
        updates?.onPause()
        super.onPause()
    }

    @Deprecated("Callback for Android's install source settings")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        updates?.onActivityResult(requestCode)
    }
}
