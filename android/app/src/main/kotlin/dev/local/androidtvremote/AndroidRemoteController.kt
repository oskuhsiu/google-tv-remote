package dev.local.androidtvremote

import android.content.Context
import dev.local.androidtvremote.discovery.TvDiscovery
import dev.local.androidtvremote.protocol.ClientIdentityRejectedException
import dev.local.androidtvremote.protocol.PairingClient
import dev.local.androidtvremote.protocol.PairingCode
import dev.local.androidtvremote.protocol.PairingRejectedException
import dev.local.androidtvremote.protocol.PairingSession
import dev.local.androidtvremote.protocol.RemoteSession
import dev.local.androidtvremote.protocol.TlsClient
import dev.local.androidtvremote.protocol.TrustChangedException
import dev.local.androidtvremote.security.ClientIdentity
import dev.local.androidtvremote.security.IdentityStore
import dev.local.androidtvremote.storage.LastTvStore
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.SocketException
import java.net.UnknownHostException
import javax.net.ssl.SSLException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class RemoteOperationException(
    val error: RemoteError,
    cause: Throwable? = null,
) : Exception(error.name, cause)

class AndroidRemoteController(
    context: Context,
    private val scope: CoroutineScope,
) : RemoteController {
    private val identityStore = IdentityStore()
    private val lastTvStore = LastTvStore(context.applicationContext)
    private val tvDiscovery = TvDiscovery(context.applicationContext)
    private val tlsClient = TlsClient(identityStore)
    private val pairingClient = PairingClient(tlsClient)
    private val lifecycleMutex = Mutex()

    private val mutableState = MutableStateFlow<RemoteState>(RemoteState.Idle)
    override val state: StateFlow<RemoteState> = mutableState.asStateFlow()
    override val discoveredCandidates: StateFlow<List<TvCandidate>> = tvDiscovery.devices

    private var rememberedRecord: LastTvRecord? = null
    private var pairing: PendingPairing? = null
    private var pairingTimeoutJob: Job? = null
    private var pairedDraft: PairedDraft? = null
    private var remoteSession: RemoteSession? = null
    private var activeSessionToken: Any? = null
    private var activeLongPress: ActiveLongPress? = null
    private var isForeground = false

    init {
        scope.launch {
            tvDiscovery.devices.collectLatest { devices ->
                lifecycleMutex.withLock {
                    if (mutableState.value is RemoteState.Discovering) {
                        mutableState.value = RemoteState.Discovering(devices)
                    }
                }
            }
        }
    }

    override suspend fun initialize() {
        lifecycleMutex.withLock {
            refreshRememberedRecordLocked()
            mutableState.value = RemoteState.Disconnected(rememberedRecord?.device)
                .takeIf { rememberedRecord != null } ?: RemoteState.Idle
        }
    }

    override suspend fun enterForeground() {
        lifecycleMutex.withLock {
            val record = refreshRememberedRecordLocked()
            when (ForegroundPolicy.action(isForeground, record != null)) {
                ForegroundAction.NONE -> Unit
                ForegroundAction.CONNECT_REMEMBERED -> {
                    isForeground = true
                    tvDiscovery.stop()
                    closeTransportsLocked()
                    connectKnownLocked(checkNotNull(record).asCandidate(), record)
                }
                ForegroundAction.START_DISCOVERY -> {
                    isForeground = true
                    startDiscoveryIfUnpairedLocked()
                }
            }
        }
    }

    override suspend fun connect(candidate: TvCandidate) {
        lifecycleMutex.withLock {
            tvDiscovery.stop()
            closeTransportsLocked()
            pairedDraft?.takeIf { it.candidate.host == candidate.host }?.let { draft ->
                completePairedDraftLocked(draft)
                return
            }
            pairedDraft = null
            val record = refreshRememberedRecordLocked()
            if (record == null) {
                beginPairingLocked(candidate, previousRecord = null)
            } else {
                connectKnownLocked(candidate, record)
            }
        }
    }

    override suspend fun connectRemembered() {
        lifecycleMutex.withLock {
            tvDiscovery.stop()
            closeTransportsLocked()
            val record = refreshRememberedRecordLocked()
            if (record == null) {
                mutableState.value = RemoteState.Idle
                return
            }
            connectKnownLocked(record.asCandidate(), record)
        }
    }

    override suspend fun submitPairingCode(code: String) {
        val parsed = PairingCode.parse(code)
            ?: throw RemoteOperationException(RemoteError.PAIRING_CODE_INVALID)
        lifecycleMutex.withLock {
            val pending = pairing ?: throw RemoteOperationException(RemoteError.PAIRING_REQUIRED)
            pairingTimeoutJob?.cancel()
            pairingTimeoutJob = null
            mutableState.value = RemoteState.Pairing(pending.candidate)
            try {
                withContext(Dispatchers.IO) { pending.session.finish(parsed) }
                val pairingFingerprint = pending.session.pairingPeerFingerprint
                val serverName = pending.session.serverName
                val draft = PairedDraft(
                    candidate = pending.candidate,
                    identity = pending.identity,
                    pairingPeerFingerprint = pairingFingerprint,
                    serverName = serverName,
                    previousRecord = pending.previousRecord,
                )
                pairedDraft = draft
                pairing = null
                scope.launch(Dispatchers.IO) { pending.session.close() }
                completePairedDraftLocked(draft)
            } catch (error: RemoteOperationException) {
                throw error
            } catch (error: Throwable) {
                withContext(Dispatchers.IO) { pending.session.close() }
                pairing = null
                val mapped = mapPairingFailure(error)
                mutableState.value = RemoteState.Failed(
                    pending.previousRecord?.device,
                    mapped,
                    recoverable = mapped != RemoteError.TRUST_CHANGED,
                )
                startDiscoveryIfUnpairedLocked()
                throw RemoteOperationException(mapped, error)
            }
        }
    }

    override suspend fun send(command: RemoteCommand, action: RemoteKeyAction) {
        require(command.supports(action)) {
            "Long key actions are only supported for SELECT"
        }
        lifecycleMutex.withLock {
            if (action == RemoteKeyAction.END_LONG) {
                val active = activeLongPress?.takeIf { it.command == command }
                    ?: return@withLock
                activeLongPress = null
                try {
                    active.session.send(command, action)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Throwable) {
                    throw RemoteOperationException(RemoteError.CONNECTION_LOST, error)
                }
                return@withLock
            }
            if (mutableState.value !is RemoteState.Connected) {
                throw RemoteOperationException(RemoteError.CONNECTION_LOST)
            }
            val session = remoteSession ?: throw RemoteOperationException(RemoteError.CONNECTION_LOST)
            if (action == RemoteKeyAction.START_LONG && activeLongPress != null) {
                throw RemoteOperationException(RemoteError.UNKNOWN)
            }
            try {
                session.send(command, action)
                when (action) {
                    RemoteKeyAction.START_LONG -> activeLongPress = ActiveLongPress(command, session)
                    RemoteKeyAction.END_LONG -> error("END_LONG handled above")
                    RemoteKeyAction.SHORT -> Unit
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (action == RemoteKeyAction.START_LONG) activeLongPress = null
                throw RemoteOperationException(RemoteError.CONNECTION_LOST, error)
            }
        }
    }

    override suspend fun disconnect() {
        lifecycleMutex.withLock {
            pairedDraft = null
            mutableState.value = RemoteState.Disconnected(rememberedRecord?.device)
            closeTransportsLocked()
            startDiscoveryIfUnpairedLocked()
        }
    }

    override suspend fun forget() {
        lifecycleMutex.withLock {
            closeTransportsLocked()
            lastTvStore.clear()
            identityStore.delete()
            pairedDraft = null
            rememberedRecord = null
            mutableState.value = RemoteState.Idle
            startDiscoveryIfUnpairedLocked()
        }
    }

    override suspend fun enterBackground() {
        lifecycleMutex.withLock {
            isForeground = false
            tvDiscovery.stop()
            pairedDraft = null
            mutableState.value = RemoteState.Disconnected(rememberedRecord?.device)
                .takeIf { rememberedRecord != null } ?: RemoteState.Idle
            closeTransportsLocked()
        }
    }

    override fun close() {
        tvDiscovery.stop()
        pairingTimeoutJob?.cancel()
        scope.launch(Dispatchers.IO + NonCancellable) {
            lifecycleMutex.withLock {
                pairedDraft = null
                closeTransportsLocked()
            }
        }
    }

    private suspend fun connectKnownLocked(candidate: TvCandidate, record: LastTvRecord) {
        mutableState.value = RemoteState.Connecting(candidate)
        try {
            val opened = openRemoteLocked(candidate.host, record.remotePeerFingerprint)
            val updated = record.copy(
                lastHost = candidate.host,
                bonjourLocatorKey = candidate.locatorKey.takeIf { candidate.source == TvSource.DISCOVERY }
                    ?: record.bonjourLocatorKey,
                lastConnectedAt = System.currentTimeMillis(),
            )
            lastTvStore.save(updated)
            rememberedRecord = updated
            remoteSession = opened
            mutableState.value = RemoteState.Connected(updated.device)
        } catch (error: ClientIdentityRejectedException) {
            beginPairingLocked(candidate, previousRecord = record)
        } catch (error: TrustChangedException) {
            mutableState.value = RemoteState.Failed(record.device, RemoteError.TRUST_CHANGED, recoverable = false)
            startDiscoveryIfUnpairedLocked()
        } catch (error: Throwable) {
            mutableState.value = RemoteState.Failed(record.device, mapConnectionFailure(error), recoverable = true)
            startDiscoveryIfUnpairedLocked()
        }
    }

    private suspend fun beginPairingLocked(
        candidate: TvCandidate,
        previousRecord: LastTvRecord?,
    ) {
        pairedDraft = null
        mutableState.value = RemoteState.Connecting(candidate)
        val identity = withContext(Dispatchers.IO) { identityStore.loadOrCreate() }
        try {
            val session = withContext(Dispatchers.IO) {
                pairingClient.start(
                    host = candidate.host,
                    clientName = CLIENT_NAME,
                    identity = identity,
                    expectedPeerFingerprint = previousRecord?.pairingPeerFingerprint,
                )
            }
            val pending = PendingPairing(candidate, identity, session, previousRecord)
            pairing = pending
            mutableState.value = RemoteState.NeedsPairing(candidate)
            pairingTimeoutJob = scope.launch {
                delay(PAIRING_INPUT_TIMEOUT_MILLIS)
                lifecycleMutex.withLock {
                    if (pairing === pending) {
                        withContext(Dispatchers.IO) { pending.session.close() }
                        pairing = null
                        mutableState.value = RemoteState.Failed(
                            pending.previousRecord?.device,
                            RemoteError.PAIRING_TIMEOUT,
                            recoverable = true,
                        )
                        startDiscoveryIfUnpairedLocked()
                    }
                }
            }
        } catch (error: Throwable) {
            val mapped = mapConnectionFailure(error)
            mutableState.value = RemoteState.Failed(
                previousRecord?.device,
                mapped,
                recoverable = mapped != RemoteError.TRUST_CHANGED,
            )
            startDiscoveryIfUnpairedLocked()
        }
    }

    private suspend fun openRemoteLocked(
        host: String,
        expectedFingerprint: String?,
    ): RemoteSession {
        val token = Any()
        activeSessionToken = token
        return RemoteSession.connect(
            host = host,
            expectedFingerprint = expectedFingerprint,
            tlsClient = tlsClient,
            scope = scope,
            onLost = { failure ->
                scope.launch {
                    lifecycleMutex.withLock {
                        if (activeSessionToken === token) {
                            activeSessionToken = null
                            remoteSession = null
                            activeLongPress = null
                            mutableState.value = RemoteState.Failed(
                                rememberedRecord?.device,
                                RemoteError.CONNECTION_LOST,
                                recoverable = true,
                            )
                            startDiscoveryIfUnpairedLocked()
                        }
                    }
                }
            },
        )
    }

    private suspend fun completePairedDraftLocked(draft: PairedDraft) {
        mutableState.value = RemoteState.Connecting(draft.candidate)
        try {
            val opened = openRemoteWithRetryLocked(
                host = draft.candidate.host,
                expectedFingerprint = draft.previousRecord?.remotePeerFingerprint,
            )
            val previousRecord = draft.previousRecord
            val device = previousRecord?.device?.copy(
                name = draft.serverName ?: previousRecord.device.name,
            ) ?: TvDevice(
                id = opened.peerFingerprint,
                name = draft.serverName ?: draft.candidate.name,
                source = draft.candidate.source,
            )
            val record = LastTvRecord(
                device = device,
                lastHost = draft.candidate.host,
                bonjourLocatorKey = draft.candidate.locatorKey.takeIf {
                    draft.candidate.source == TvSource.DISCOVERY
                } ?: previousRecord?.bonjourLocatorKey,
                lastConnectedAt = System.currentTimeMillis(),
                clientIdentityFingerprint = draft.identity.fingerprint,
                pairingPeerFingerprint = draft.pairingPeerFingerprint,
                remotePeerFingerprint = opened.peerFingerprint,
            )
            lastTvStore.save(record)
            rememberedRecord = record
            remoteSession = opened
            pairedDraft = null
            mutableState.value = RemoteState.Connected(device)
        } catch (error: Throwable) {
            val mapped = mapConnectionFailure(error)
            mutableState.value = RemoteState.Failed(
                draft.previousRecord?.device,
                mapped,
                recoverable = mapped != RemoteError.TRUST_CHANGED,
            )
            startDiscoveryIfUnpairedLocked()
            throw RemoteOperationException(mapped, error)
        }
    }

    private fun startDiscoveryIfUnpairedLocked() {
        if (!ForegroundPolicy.allowsAutomaticDiscovery(isForeground, rememberedRecord != null)) {
            tvDiscovery.stop()
            return
        }
        tvDiscovery.start()
        if (mutableState.value is RemoteState.Idle || mutableState.value == RemoteState.Disconnected(null)) {
            mutableState.value = RemoteState.Discovering(tvDiscovery.devices.value)
        }
    }

    private suspend fun openRemoteWithRetryLocked(
        host: String,
        expectedFingerprint: String?,
    ): RemoteSession {
        var lastFailure: Throwable? = null
        for (attempt in 1..3) {
            delay(checkNotNull(RetryPolicy.delayMillis(attempt)))
            try {
                return openRemoteLocked(host, expectedFingerprint)
            } catch (error: TrustChangedException) {
                throw error
            } catch (error: Throwable) {
                activeSessionToken = null
                lastFailure = error
            }
        }
        throw checkNotNull(lastFailure)
    }

    private fun loadValidRecordOrClear(): LastTvRecord? {
        val record = lastTvStore.load()
        val identity = identityStore.load()
        if (record == null && identity == null) return null
        if (record != null && identity != null && TrustTupleValidator.isComplete(record, identity.fingerprint)) {
            return record
        }
        lastTvStore.clear()
        identityStore.delete()
        return null
    }

    private fun refreshRememberedRecordLocked(): LastTvRecord? =
        loadValidRecordOrClear().also { rememberedRecord = it }

    private suspend fun closeTransportsLocked() {
        pairingTimeoutJob?.cancel()
        pairingTimeoutJob = null
        val pairingToClose = pairing?.session
        pairing = null
        val remoteToClose = remoteSession
        val longPressToEnd = activeLongPress
        activeLongPress = null
        activeSessionToken = null
        remoteSession = null
        withContext(NonCancellable) {
            withContext(Dispatchers.IO) { pairingToClose?.close() }
            remoteToClose?.closeAfterEndingLongPress(
                longPressToEnd?.command.takeIf { longPressToEnd?.session === remoteToClose },
            )
        }
    }

    private fun mapPairingFailure(error: Throwable): RemoteError = when (error) {
        is IllegalArgumentException -> RemoteError.PAIRING_CODE_INVALID
        is PairingRejectedException -> RemoteError.PAIRING_REJECTED
        is SocketTimeoutException -> RemoteError.PAIRING_TIMEOUT
        else -> mapConnectionFailure(error)
    }

    private fun mapConnectionFailure(error: Throwable): RemoteError = when (error) {
        is TrustChangedException -> RemoteError.TRUST_CHANGED
        is UnknownHostException -> RemoteError.TV_NOT_FOUND
        is ConnectException, is NoRouteToHostException, is SocketTimeoutException, is SocketException ->
            RemoteError.NETWORK_UNREACHABLE
        is SSLException -> RemoteError.PAIRING_REQUIRED
        else -> RemoteError.UNKNOWN
    }

    private data class PendingPairing(
        val candidate: TvCandidate,
        val identity: ClientIdentity,
        val session: PairingSession,
        val previousRecord: LastTvRecord?,
    )

    private data class PairedDraft(
        val candidate: TvCandidate,
        val identity: ClientIdentity,
        val pairingPeerFingerprint: String,
        val serverName: String?,
        val previousRecord: LastTvRecord?,
    )

    private data class ActiveLongPress(
        val command: RemoteCommand,
        val session: RemoteSession,
    )

    companion object {
        private const val CLIENT_NAME = "TV Remote"
        private const val PAIRING_INPUT_TIMEOUT_MILLIS = 60_000L
    }
}

private fun LastTvRecord.asCandidate(): TvCandidate = TvCandidate(
    locatorKey = bonjourLocatorKey ?: "remembered",
    name = device.name,
    host = lastHost,
    source = device.source,
)
