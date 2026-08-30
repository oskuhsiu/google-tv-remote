package dev.local.androidtvremote

import android.app.Application
import android.content.Context
import dev.local.androidtvremote.floating.FloatingRemotePreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async

class RemoteApplication : Application() {
    val remoteRuntime: RemoteRuntime by lazy { RemoteRuntime(this) }
}

class RemoteRuntime(context: Context) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val controller: RemoteController = AndroidRemoteController(context.applicationContext, scope)
    val floatingPreferences = FloatingRemotePreferences(context.applicationContext)

    private val initialization = scope.async { controller.initialize() }

    suspend fun awaitInitialized() {
        initialization.await()
    }
}
