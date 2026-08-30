package dev.local.androidtvremote.protocol

import com.google.polo.wire.protobuf.PoloProto
import dev.local.androidtvremote.security.ClientIdentity
import java.io.Closeable
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.security.cert.X509Certificate
import java.security.interfaces.RSAPublicKey

class PairingRejectedException(message: String) : Exception(message)

class PairingClient(
    private val tlsClient: TlsClient,
    private val frameReader: DelimitedFrameReader = DelimitedFrameReader(),
) {
    fun start(
        host: String,
        clientName: String,
        identity: ClientIdentity,
        expectedPeerFingerprint: String?,
    ): PairingSession {
        val connection = tlsClient.connectPairing(host, expectedPeerFingerprint)
        val session = PairingSession(connection, identity, frameReader)
        return try {
            session.negotiate(clientName)
            session
        } catch (error: Throwable) {
            session.close()
            throw error
        }
    }
}

class PairingSession internal constructor(
    private val connection: TlsConnection,
    private val identity: ClientIdentity,
    private val frameReader: DelimitedFrameReader,
) : Closeable {
    private val input: InputStream = connection.socket.inputStream
    private val output: OutputStream = connection.socket.outputStream

    var serverName: String? = null
        private set

    val pairingPeerFingerprint: String
        get() = connection.peerFingerprint

    internal fun negotiate(clientName: String) {
        write(
            message().setPairingRequest(
                PoloProto.PairingRequest.newBuilder()
                    .setServiceName(SERVICE_NAME)
                    .setClientName(clientName),
            ).build(),
        )

        val requestAck = readOk()
        if (!requestAck.hasPairingRequestAck()) throw PairingRejectedException("Missing pairing request acknowledgement")
        serverName = requestAck.pairingRequestAck.serverName.takeIf(String::isNotBlank)

        write(
            message().setOptions(
                PoloProto.Options.newBuilder()
                    .setPreferredRole(PoloProto.Options.RoleType.ROLE_TYPE_INPUT)
                    .addInputEncodings(hexEncoding()),
            ).build(),
        )

        val options = readOk()
        if (!options.hasOptions()) throw PairingRejectedException("Missing pairing options")

        write(
            message().setConfiguration(
                PoloProto.Configuration.newBuilder()
                    .setClientRole(PoloProto.Options.RoleType.ROLE_TYPE_INPUT)
                    .setEncoding(hexEncoding()),
            ).build(),
        )

        val configurationAck = readOk()
        if (!configurationAck.hasConfigurationAck()) {
            throw PairingRejectedException("Missing pairing configuration acknowledgement")
        }
    }

    fun finish(code: PairingCode) {
        val clientKey = identity.certificate.publicKey as? RSAPublicKey
            ?: throw PairingRejectedException("Client identity is not RSA")
        val serverKey = connection.peerCertificate.publicKey as? RSAPublicKey
            ?: throw PairingRejectedException("TV identity is not RSA")
        val secret = PairingSecret.calculate(
            clientKey.modulus,
            clientKey.publicExponent,
            serverKey.modulus,
            serverKey.publicExponent,
            code,
        )
        write(
            message().setSecret(PoloProto.Secret.newBuilder().setSecret(com.google.protobuf.ByteString.copyFrom(secret)))
                .build(),
        )
        val acknowledgement = readOk()
        if (!acknowledgement.hasSecretAck()) throw PairingRejectedException("TV rejected pairing secret")
    }

    private fun readOk(): PoloProto.OuterMessage {
        val payload = frameReader.read(input) ?: throw EOFException("TV closed the pairing connection")
        val response = PoloProto.OuterMessage.parseFrom(payload)
        if (response.status != PoloProto.OuterMessage.Status.STATUS_OK) {
            throw PairingRejectedException("TV returned pairing status ${response.status.number}")
        }
        return response
    }

    @Synchronized
    private fun write(value: PoloProto.OuterMessage) {
        val frame = Framing.frame(value.toByteArray())
        output.write(frame)
        output.flush()
    }

    override fun close() {
        runCatching { connection.socket.close() }
    }

    companion object {
        private const val SERVICE_NAME = "atvremote"

        private fun message(): PoloProto.OuterMessage.Builder = PoloProto.OuterMessage.newBuilder()
            .setProtocolVersion(2)
            .setStatus(PoloProto.OuterMessage.Status.STATUS_OK)

        private fun hexEncoding(): PoloProto.Options.Encoding = PoloProto.Options.Encoding.newBuilder()
            .setType(PoloProto.Options.Encoding.EncodingType.ENCODING_TYPE_HEXADECIMAL)
            .setSymbolLength(6)
            .build()
    }
}
