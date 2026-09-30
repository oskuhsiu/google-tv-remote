import Foundation

enum WolPacket {
    static func normalizedMAC(_ input: String) -> String? {
        guard let bytes = macBytes(input) else { return nil }
        return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    static func make(macAddress: String) -> Data? {
        guard let bytes = macBytes(macAddress) else { return nil }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }
        return packet
    }

    private static func macBytes(_ input: String) -> [UInt8]? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex: String
        if value.contains(":") || value.contains("-") {
            let separator: Character = value.contains(":") ? ":" : "-"
            let parts = value.split(separator: separator, omittingEmptySubsequences: false)
            guard parts.count == 6, parts.allSatisfy({ $0.utf8.count == 2 }) else { return nil }
            hex = parts.joined()
        } else {
            hex = value
        }
        guard hex.utf8.count == 12, hex.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else { return nil }
        let characters = Array(hex)
        let bytes = stride(from: 0, to: 12, by: 2).compactMap {
            UInt8(String(characters[$0...($0 + 1)]), radix: 16)
        }
        // Broadcast, multicast and all-zero addresses cannot identify a TV interface.
        guard bytes.count == 6, bytes.contains(where: { $0 != 0 }), bytes[0] & 1 == 0 else {
            return nil
        }
        return bytes
    }
}
