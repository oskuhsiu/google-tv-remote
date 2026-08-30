package dev.local.androidtvremote.protocol

import dev.local.androidtvremote.RemoteCommand
import dev.local.androidtvremote.RemoteKeyAction
import remote.Remotemessage.RemoteDirection
import remote.Remotemessage.RemoteKeyCode
import remote.Remotemessage.RemoteKeyInject
import remote.Remotemessage.RemoteMessage
import remote.Remotemessage.RemotePingResponse

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
}

private fun RemoteKeyAction.toRemoteDirection(): RemoteDirection = when (this) {
    RemoteKeyAction.SHORT -> RemoteDirection.SHORT
    RemoteKeyAction.START_LONG -> RemoteDirection.START_LONG
    RemoteKeyAction.END_LONG -> RemoteDirection.END_LONG
}
