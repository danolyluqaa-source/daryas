package com.daryas.ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.NotificationCompat
import java.util.Locale

/**
 * Visible microphone foreground service.
 *
 * Android requires a persistent notification for microphone use in background.
 * SpeechRecognizer availability and continuous recognition depend on the device,
 * language pack, Google speech services and battery policy.
 */
class QaraWakeService : Service(), RecognitionListener {
    companion object {
        const val ACTION_START = "com.daryas.ai.WAKE_START"
        const val ACTION_STOP = "com.daryas.ai.WAKE_STOP"
        private const val CHANNEL_ID = "qara_wake_channel"
        private const val NOTIFICATION_ID = 7102
        @Volatile var isRunning: Boolean = false
            private set
    }

    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var listening = false
    private var wakeDetectedAt = 0L

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        try {
            startForeground(NOTIFICATION_ID, buildNotification(
                "گوێگرتنی وشەی بانگکردن چالاکە: قەرە"
            ))
            isRunning = true
            beginRecognition()
        } catch (error: Exception) {
            isRunning = false
            stopSelf()
        }
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "قەرە - گوێگرتنی دەنگ",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "ئاگادارکردنەوەی بەردەوام بۆ گوێگرتنی وشەی قەرە"
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(message: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            this, 10, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("قەرە چالاکە")
            .setContentText(message)
            .setContentIntent(pending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun beginRecognition() {
        if (!isRunning || !SpeechRecognizer.isRecognitionAvailable(this)) {
            updateNotification("ناسینەوەی دەنگ لەم ئامێرەدا بەردەست نییە")
            return
        }
        try {
            if (recognizer == null) {
                recognizer = SpeechRecognizer.createSpeechRecognizer(this)
                recognizer?.setRecognitionListener(this)
            }
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ar-IQ")
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "ar-IQ")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 4)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            }
            listening = true
            recognizer?.startListening(intent)
        } catch (_: Exception) {
            listening = false
            scheduleRestart(2500)
        }
    }

    private fun scheduleRestart(delay: Long = 900) {
        handler.removeCallbacksAndMessages(null)
        if (isRunning) handler.postDelayed({ beginRecognition() }, delay)
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun containsWakeWord(text: String): Boolean {
        val normalized = text.lowercase(Locale.ROOT)
            .replace(" ", "")
            .replace("‌", "")
        return normalized.contains("قەرە") ||
            normalized.contains("قارا") ||
            normalized.contains("qara") ||
            normalized.contains("kara")
    }

    override fun onResults(results: android.os.Bundle?) {
        listening = false
        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        val recognized = matches?.joinToString(" ") ?: ""
        if (containsWakeWord(recognized)) {
            val now = System.currentTimeMillis()
            if (now - wakeDetectedAt > 5000) {
                wakeDetectedAt = now
                updateNotification("قەرە بانگ کرا. بۆ دەستپێکردنی گفتوگۆ ئاگادارکردنەوەکە بکەرەوە.")
            }
        }
        scheduleRestart(650)
    }

    override fun onError(error: Int) {
        listening = false
        // Common transient errors are retried. A permanent service failure is not hidden.
        scheduleRestart(if (error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY) 1800 else 1200)
    }

    override fun onReadyForSpeech(params: android.os.Bundle?) { listening = true }
    override fun onBeginningOfSpeech() {}
    override fun onRmsChanged(rmsdB: Float) {}
    override fun onBufferReceived(buffer: ByteArray?) {}
    override fun onEndOfSpeech() { listening = false }
    override fun onPartialResults(partialResults: android.os.Bundle?) {
        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        val recognized = matches?.joinToString(" ") ?: ""
        if (containsWakeWord(recognized)) {
            updateNotification("قەرە بانگ کرا. بۆ قسەکردن ئاگادارکردنەوەکە بکەرەوە.")
        }
    }
    override fun onEvent(eventType: Int, params: android.os.Bundle?) {}

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Keep the explicit user-enabled foreground service alive after app swipe-away.
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacksAndMessages(null)
        try {
            recognizer?.cancel()
            recognizer?.destroy()
        } catch (_: Exception) {}
        recognizer = null
        listening = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
