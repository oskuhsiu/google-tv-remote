package dev.local.androidtvremote.protocol

import java.math.BigInteger
import java.security.MessageDigest

object PairingSecret {
    fun calculate(
        clientModulus: BigInteger,
        clientExponent: BigInteger,
        serverModulus: BigInteger,
        serverExponent: BigInteger,
        code: PairingCode,
    ): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(unsignedBytes(clientModulus))
        digest.update(unsignedBytes(clientExponent))
        digest.update(unsignedBytes(serverModulus))
        digest.update(unsignedBytes(serverExponent))
        digest.update(hexBytes(code.value.substring(2)))
        val result = digest.digest()
        require((result[0].toInt() and 0xFF) == code.value.substring(0, 2).toInt(16)) {
            "Pairing code does not match the certificate proof"
        }
        return result
    }

    private fun unsignedBytes(value: BigInteger): ByteArray {
        require(value.signum() >= 0) { "RSA values must be unsigned" }
        var hex = value.toString(16)
        if (hex.length % 2 != 0) hex = "0$hex"
        return hexBytes(hex)
    }

    private fun hexBytes(value: String): ByteArray =
        ByteArray(value.length / 2) { index ->
            value.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
}

