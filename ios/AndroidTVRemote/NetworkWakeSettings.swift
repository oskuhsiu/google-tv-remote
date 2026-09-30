import Foundation

struct NetworkWakeSettings: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case manual
    }

    enum Capability: String, Codable, Sendable {
        case unverified
        case verified
        case unsupported
    }

    let macAddress: String
    let source: Source
    let capability: Capability

    init?(macAddress: String, capability: Capability = .unverified) {
        guard let mac = WolPacket.normalizedMAC(macAddress) else { return nil }
        self.macAddress = mac
        source = .manual
        self.capability = capability
    }

    private enum CodingKeys: String, CodingKey {
        case macAddress, source, capability
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawMAC = try values.decode(String.self, forKey: .macAddress)
        guard let mac = WolPacket.normalizedMAC(rawMAC) else {
            throw DecodingError.dataCorruptedError(
                forKey: .macAddress, in: values, debugDescription: "Invalid device MAC address"
            )
        }
        macAddress = mac
        source = try values.decode(Source.self, forKey: .source)
        capability = try values.decode(Capability.self, forKey: .capability)
    }
}
