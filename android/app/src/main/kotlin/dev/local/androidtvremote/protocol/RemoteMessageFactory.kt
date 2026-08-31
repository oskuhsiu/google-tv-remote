package dev.local.androidtvremote.protocol

import dev.local.androidtvremote.RemoteCommand
import dev.local.androidtvremote.RemoteKeyAction
import remote.Remotemessage.RemoteDirection
import remote.Remotemessage.RemoteKeyCode
import remote.Remotemessage.RemoteKeyInject
import remote.Remotemessage.RemoteMessage
import remote.Remotemessage.RemotePingResponse
import remote.Remotemessage.RemoteVoiceBegin
import remote.Remotemessage.RemoteVoiceEnd
import remote.Remotemessage.RemoteVoicePayload
import com.google.protobuf.ByteString

object RemoteMessageFactory {
    fun key(
        command: RemoteCommand,
        action: RemoteKeyAction = RemoteKeyAction.SHORT,
    ): RemoteMessage {
        require(command.supports(action)) {
            "Long key actions are only supported for SELECT"
        }
        return key(command.keyCode, action)
    }

    fun search(): RemoteMessage = key(VOICE_SEARCH_KEY_CODE, RemoteKeyAction.SHORT)

    fun voiceBegin(sessionId: Int): RemoteMessage = RemoteMessage.newBuilder()
        .setRemoteVoiceBegin(RemoteVoiceBegin.newBuilder().setSessionId(sessionId))
        .build()

    fun voicePayload(sessionId: Int, samples: ByteArray): RemoteMessage {
        require(samples.size <= MAX_VOICE_PAYLOAD_BYTES) { "Voice payload is too large" }
        return RemoteMessage.newBuilder()
            .setRemoteVoicePayload(
                RemoteVoicePayload.newBuilder()
                    .setSessionId(sessionId)
                    .setSamples(ByteString.copyFrom(samples)),
            ).build()
    }

    fun voiceEnd(sessionId: Int): RemoteMessage = RemoteMessage.newBuilder()
        .setRemoteVoiceEnd(RemoteVoiceEnd.newBuilder().setSessionId(sessionId))
        .build()

    fun pong(value: Int): RemoteMessage = RemoteMessage.newBuilder()
        .setRemotePingResponse(RemotePingResponse.newBuilder().setVal1(value))
        .build()

    private fun key(keyCode: Int, action: RemoteKeyAction): RemoteMessage {
        val remoteKey = requireNotNull(RemoteKeyCode.forNumber(keyCode))
        return RemoteMessage.newBuilder()
            .setRemoteKeyInject(
                RemoteKeyInject.newBuilder()
                    .setKeyCode(remoteKey)
                    .setDirection(action.toRemoteDirection()),
            )
            .build()
    }

    const val VOICE_SEARCH_KEY_CODE = 84
    const val MAX_VOICE_PAYLOAD_BYTES = 20_480
}

private fun RemoteKeyAction.toRemoteDirection(): RemoteDirection = when (this) {
    RemoteKeyAction.SHORT -> RemoteDirection.SHORT
    RemoteKeyAction.START_LONG -> RemoteDirection.START_LONG
    RemoteKeyAction.END_LONG -> RemoteDirection.END_LONG
}
