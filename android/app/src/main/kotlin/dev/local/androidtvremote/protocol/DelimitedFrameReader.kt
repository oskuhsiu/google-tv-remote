package dev.local.androidtvremote.protocol

import java.io.EOFException
import java.io.IOException
import java.io.InputStream

open class FrameException(message: String) : IOException(message)

class OversizedFrameException(size: Int, maxSize: Int) :
    FrameException("Frame size $size exceeds the $maxSize-byte limit")

class DelimitedFrameReader(
    private val maxFrameSize: Int = DEFAULT_MAX_FRAME_SIZE,
) {
    fun read(input: InputStream): ByteArray? {
        val first = input.read()
        if (first == -1) return null

        var length = 0
        var byte = first
        for (index in 0 until MAX_VARINT_BYTES) {
            if (index == MAX_VARINT_BYTES - 1 && (byte and 0xF0) != 0) {
                throw FrameException("Malformed frame length")
            }
            length = length or ((byte and 0x7F) shl (index * 7))
            if ((byte and 0x80) == 0) {
                if (length > maxFrameSize) throw OversizedFrameException(length, maxFrameSize)
                return readPayload(input, length)
            }
            if (index == MAX_VARINT_BYTES - 1) throw FrameException("Frame length varint is too long")
            byte = input.read()
            if (byte == -1) throw EOFException("Truncated frame length")
        }
        throw FrameException("Malformed frame length")
    }

    private fun readPayload(input: InputStream, length: Int): ByteArray {
        val payload = ByteArray(length)
        var offset = 0
        while (offset < length) {
            val count = input.read(payload, offset, length - offset)
            if (count == -1) throw EOFException("Truncated frame payload")
            offset += count
        }
        return payload
    }

    companion object {
        const val DEFAULT_MAX_FRAME_SIZE = 1024 * 1024
        private const val MAX_VARINT_BYTES = 5
    }
}

object Framing {
    fun frame(payload: ByteArray): ByteArray = encodeLength(payload.size) + payload

    fun encodeLength(length: Int): ByteArray {
        require(length >= 0)
        var value = length
        val bytes = ArrayList<Byte>(5)
        do {
            var next = value and 0x7F
            value = value ushr 7
            if (value != 0) next = next or 0x80
            bytes += next.toByte()
        } while (value != 0)
        return bytes.toByteArray()
    }
}

