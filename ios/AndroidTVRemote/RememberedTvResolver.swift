import Darwin
import Foundation

/// Resolves only the saved instance; never browses or publishes candidates.
@MainActor
final class RememberedTvResolver: NSObject, @preconcurrency NetServiceDelegate {
    private var service: NetService?
    private var completion: ((String?) -> Void)?
    func resolve(_ locator: BonjourLocator, completion: @escaping (String?) -> Void) {
        cancel()
        let type = locator.type.hasSuffix(".") ? String(locator.type.dropLast()) : locator.type
        guard locator.domain == "local.", type == "_androidtvremote2._tcp", !locator.name.isEmpty else {
            completion(nil); return
        }
        self.completion = completion
        let service = NetService(domain: locator.domain, type: type + ".", name: locator.name)
        self.service = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }
    func cancel() {
        service?.delegate = nil
        service?.stop()
        service = nil
        completion = nil
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard service === sender else { return }
        let host = sender.addresses?.compactMap(Self.host).first
        finish(host)
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        guard service === sender else { return }
        finish(nil)
    }
    private func finish(_ host: String?) {
        let callback = completion
        cancel()
        callback?(host)
    }
    private static func host(_ data: Data) -> String? {
        guard data.count >= MemoryLayout<sockaddr>.size else { return nil }
        return data.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress?.assumingMemoryBound(to: sockaddr.self),
                  address.pointee.sa_family == sa_family_t(AF_INET) || address.pointee.sa_family == sa_family_t(AF_INET6) else { return nil }
            var result = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(data.count), &result, socklen_t(result.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
            return String(cString: result)
        }
    }
}

extension LastTvRecord {
    func replacingHost(_ host: String, connectedAt: Date? = nil) -> LastTvRecord {
        LastTvRecord(persistentDeviceID: persistentDeviceID, name: name, clientIdentityFingerprint: clientIdentityFingerprint,
            pairingPeerFingerprint: pairingPeerFingerprint, remotePeerFingerprint: remotePeerFingerprint,
            lastHost: host, bonjourLocator: bonjourLocator, source: source,
            lastConnectedAt: connectedAt ?? lastConnectedAt)
    }
}
