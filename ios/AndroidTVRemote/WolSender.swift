import Darwin
import Foundation
import Network

protocol WolSending: Sendable {
    /// Success means the local socket accepted the packet, not that the TV woke.
    func send(macAddress: String) async throws
}

enum WolSendError: Error, Equatable {
    case invalidMAC
    case localNetworkUnavailable
    case sendFailed
}

struct LocalNetworkWolSender: WolSending {
    func send(macAddress: String) async throws {
        guard let packet = WolPacket.make(macAddress: macAddress) else {
            throw WolSendError.invalidMAC
        }
        let interface = try await ActiveWolInterface.resolve()
        try Task.checkCancellation()
        // This nonisolated async function runs off the UI actor; socket calls are bounded.
        try Self.send(packet: packet, interface: interface)
    }

    private static func send(packet: Data, interface: ActiveWolInterface) throws {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else {
            throw WolSendError.localNetworkUnavailable
        }
        defer { freeifaddrs(first) }

        var sent = false
        var foundTarget = false
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            let value = entry.pointee
            guard String(cString: value.ifa_name) == interface.name,
                  value.ifa_flags & UInt32(IFF_UP | IFF_RUNNING | IFF_BROADCAST) == UInt32(IFF_UP | IFF_RUNNING | IFF_BROADCAST),
                  value.ifa_flags & UInt32(IFF_LOOPBACK | IFF_POINTOPOINT) == 0,
                  let address = value.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  let netmask = value.ifa_netmask else { continue }
            let local = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee
            let mask = UnsafeRawPointer(netmask).assumingMemoryBound(to: sockaddr_in.self).pointee
            let broadcast = local.sin_addr.s_addr | ~mask.sin_addr.s_addr
            guard local.sin_addr.s_addr != 0, mask.sin_addr.s_addr != 0,
                  mask.sin_addr.s_addr != UInt32.max, broadcast != UInt32.max else { continue }
            foundTarget = true
            try Task.checkCancellation()
            if sendDatagram(packet, local: local, broadcast: broadcast, index: interface.index) {
                sent = true
            }
        }
        guard foundTarget else { throw WolSendError.localNetworkUnavailable }
        guard sent else { throw WolSendError.sendFailed }
    }

    private static func sendDatagram(
        _ packet: Data, local: sockaddr_in, broadcast: UInt32, index: UInt32
    ) -> Bool {
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        let flags = fcntl(descriptor, F_GETFL)
        // An explicit one-packet test should fail promptly if the socket cannot send.
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { return false }
        var enabled: Int32 = 1
        var boundIndex = index
        guard setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled))) == 0,
              setsockopt(descriptor, IPPROTO_IP, IP_BOUND_IF, &boundIndex, socklen_t(MemoryLayout.size(ofValue: boundIndex))) == 0 else {
            return false
        }
        var source = local
        source.sin_port = 0
        let bound = withUnsafePointer(to: &source) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return false }
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = UInt16(9).bigEndian
        destination.sin_addr.s_addr = broadcast
        let count = packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &destination) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return count == packet.count
    }
}

private struct ActiveWolInterface: Sendable {
    let name: String
    let index: UInt32

    static func resolve() async throws -> Self {
        let request = WolPathRequest()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.start(continuation)
            }
        } onCancel: {
            request.finish(.failure(CancellationError()))
        }
    }
}

/// A one-shot default-path observation. A cellular, VPN, or absent path fails closed.
private final class WolPathRequest: @unchecked Sendable {
    private let lock = NSLock()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.local.AndroidTVRemote.wol-path")
    private var continuation: CheckedContinuation<ActiveWolInterface, Error>?
    private var result: Result<ActiveWolInterface, Error>?

    func start(_ continuation: CheckedContinuation<ActiveWolInterface, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        self.continuation = continuation
        lock.unlock()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            // Apple's path interface list is ordered by preference. Never skip a
            // preferred cellular/tunnel interface to find an otherwise available Wi-Fi.
            guard path.status == .satisfied,
                  !path.usesInterfaceType(.other), !path.usesInterfaceType(.cellular),
                  let interface = path.availableInterfaces.first,
                  interface.type == .wifi || interface.type == .wiredEthernet,
                  path.usesInterfaceType(interface.type) else {
                self.finish(.failure(WolSendError.localNetworkUnavailable))
                return
            }
            self.finish(.success(ActiveWolInterface(name: interface.name, index: UInt32(interface.index))))
        }
        monitor.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.finish(.failure(WolSendError.localNetworkUnavailable))
        }
    }

    func finish(_ result: Result<ActiveWolInterface, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        monitor.cancel()
        continuation?.resume(with: result)
    }
}
