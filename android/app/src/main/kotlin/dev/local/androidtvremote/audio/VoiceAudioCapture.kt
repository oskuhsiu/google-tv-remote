package dev.local.androidtvremote.audio

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext

interface VoiceAudioCapture {
    suspend fun capture(onChunk: suspend (ByteArray) -> Unit)
    fun stop()
}

class AudioRecordVoiceCapture(
    context: Context,
    private val chunkByteCount: Int,
) : VoiceAudioCapture {
    init {
        require(chunkByteCount > 0)
    }

    private val applicationContext = context.applicationContext
    private val recordLock = Any()
    private var activeRecord: AudioRecord? = null
    private val stopRequested = AtomicBoolean(false)

    override suspend fun capture(onChunk: suspend (ByteArray) -> Unit) = withContext(Dispatchers.IO) {
        if (ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("Microphone permission is not granted")
        }
        val minBufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        check(minBufferSize > 0) { "AudioRecord does not support the voice format" }
        val record = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT,
            maxOf(minBufferSize, chunkByteCount * 2),
        )
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            error("AudioRecord failed to initialize")
        }
        synchronized(recordLock) {
            if (activeRecord != null) {
                record.release()
                error("Voice capture is already active")
            }
            activeRecord = record
        }
        val accumulator = PcmChunkAccumulator(chunkByteCount)
        val readBuffer = ByteArray(chunkByteCount)
        try {
            synchronized(recordLock) {
                if (stopRequested.get()) return@withContext
                record.startRecording()
                check(record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    "AudioRecord failed to start"
                }
            }
            while (currentCoroutineContext().isActive) {
                val count = record.read(readBuffer, 0, readBuffer.size, AudioRecord.READ_BLOCKING)
                if (count <= 0) {
                    check(stopRequested.get()) { "AudioRecord read failed: $count" }
                    break
                }
                accumulator.append(readBuffer, count).forEach { onChunk(it) }
            }
            accumulator.finish()?.let { onChunk(it) }
        } finally {
            synchronized(recordLock) {
                if (activeRecord === record) activeRecord = null
                runCatching {
                    if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) record.stop()
                }
                record.release()
            }
        }
    }

    override fun stop() {
        stopRequested.set(true)
        synchronized(recordLock) {
            activeRecord?.let { record ->
                runCatching {
                    if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) record.stop()
                }
            }
        }
    }

    companion object {
        const val SAMPLE_RATE = 8_000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    }
}

class PcmChunkAccumulator(
    private val chunkSize: Int,
) {
    init {
        require(chunkSize > 0)
    }

    private val pending = ByteArray(chunkSize)
    private var pendingSize = 0

    fun append(bytes: ByteArray, count: Int = bytes.size): List<ByteArray> {
        require(count in 0..bytes.size)
        val chunks = mutableListOf<ByteArray>()
        var sourceOffset = 0
        while (sourceOffset < count) {
            val copied = minOf(chunkSize - pendingSize, count - sourceOffset)
            bytes.copyInto(pending, pendingSize, sourceOffset, sourceOffset + copied)
            sourceOffset += copied
            pendingSize += copied
            if (pendingSize == chunkSize) {
                chunks += pending.copyOf()
                pendingSize = 0
            }
        }
        return chunks
    }

    fun finish(): ByteArray? {
        if (pendingSize == 0) return null
        return pending.copyOf().also { chunk ->
            chunk.fill(0, fromIndex = pendingSize)
            pendingSize = 0
        }
    }
}
