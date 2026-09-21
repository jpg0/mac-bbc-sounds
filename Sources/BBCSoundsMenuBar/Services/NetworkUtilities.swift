import Foundation
import Darwin

/// Utilities for querying local network interfaces and resolving LAN IP addresses.
public enum NetworkUtilities {

    /// Custom resolver for tests to override the resolved IPv4 address.
    public static var customIPv4Resolver: (() -> String?)?

    /// Resolves the primary local IPv4 address (e.g., Wi-Fi or Ethernet on the LAN),
    /// ignoring loopback (127.0.0.1) and link-local (169.254.x.x) addresses.
    public static func primaryIPv4Address() -> String? {
        if let custom = customIPv4Resolver {
            return custom()
        }

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        var candidates: [(name: String, address: String, isPrimaryEN: Bool)] = []

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard let sockaddrPtr = interface.ifa_addr else { continue }

            let family = sockaddrPtr.pointee.sa_family
            let flags = Int32(interface.ifa_flags)

            // Must be IPv4, up and running, and not loopback
            guard family == UInt8(AF_INET) else { continue }
            guard (flags & IFF_UP) != 0 else { continue }
            guard (flags & IFF_RUNNING) != 0 else { continue }
            guard (flags & IFF_LOOPBACK) == 0 else { continue }

            let name = String(cString: interface.ifa_name)

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                sockaddrPtr,
                socklen_t(sockaddrPtr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            if result == 0 {
                let address = String(cString: hostname)
                // Filter loopback and IPv4 link-local (APIPA: 169.254.0.0/16)
                if !address.hasPrefix("127.") && !address.hasPrefix("169.254.") {
                    let isPrimaryEN = name == "en0" || name.hasPrefix("en")
                    candidates.append((name: name, address: address, isPrimaryEN: isPrimaryEN))
                }
            }
        }

        // Prioritize en0 (standard primary interface on macOS), then other en* interfaces
        if let en0 = candidates.first(where: { $0.name == "en0" }) {
            return en0.address
        }
        if let en = candidates.first(where: { $0.isPrimaryEN }) {
            return en.address
        }
        return candidates.first?.address
    }
}
