import Foundation
import Darwin

/// Discovered UPnP service representation containing parsed SSDP headers.
public final class SSDPService {
    public let host: String
    public let responseHeaders: [String: String]?
    public let location: String?
    public let server: String?
    public let searchTarget: String?
    public let uniqueServiceName: String?

    public init(host: String, response: String) {
        self.host = host
        var headers: [String: String] = [:]
        let lines = response.components(separatedBy: "\r\n")
        for line in lines {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces).uppercased()
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        self.responseHeaders = headers
        self.location = headers["LOCATION"]
        self.server = headers["SERVER"]
        self.searchTarget = headers["ST"]
        self.uniqueServiceName = headers["USN"]
    }
}

/// Delegate protocol notifying discovery events.
public protocol SSDPDiscoveryDelegate: AnyObject {
    func ssdpDiscovery(_ discovery: SSDPDiscovery, didDiscoverService service: SSDPService)
    func ssdpDiscovery(_ discovery: SSDPDiscovery, didFinishWithError error: Error)
    func ssdpDiscoveryDidStart(_ discovery: SSDPDiscovery)
    func ssdpDiscoveryDidFinish(_ discovery: SSDPDiscovery)
}

public extension SSDPDiscoveryDelegate {
    func ssdpDiscovery(_ discovery: SSDPDiscovery, didDiscoverService service: SSDPService) {}
    func ssdpDiscovery(_ discovery: SSDPDiscovery, didFinishWithError error: Error) {}
    func ssdpDiscoveryDidStart(_ discovery: SSDPDiscovery) {}
    func ssdpDiscoveryDidFinish(_ discovery: SSDPDiscovery) {}
}

/// Native Swift SSDP discovery client using non-blocking UDP sockets and DispatchSource.
public class SSDPDiscovery {
    public weak var delegate: SSDPDiscoveryDelegate?

    private let queue = DispatchQueue(label: "com.bbcsounds.ssdp", qos: .utility)
    private var readSource: DispatchSourceRead?
    private var timer: DispatchSourceTimer?
    private var socketFD: Int32 = -1
    private var _isDiscovering: Bool = false
    private let lock = NSLock()

    public var isDiscovering: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isDiscovering
    }

    public init() {}

    deinit {
        stop()
    }

    public func discoverService(
        forDuration duration: TimeInterval = 10,
        searchTarget: String = "ssdp:all",
        port: Int32 = 1900
    ) {
        stop()

        lock.lock()
        _isDiscovering = true
        lock.unlock()

        delegate?.ssdpDiscoveryDidStart(self)

        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.startListeningAndSendSearch(
                    searchTarget: searchTarget,
                    port: in_port_t(port),
                    duration: duration
                )
            } catch {
                self.lock.lock()
                self._isDiscovering = false
                self.lock.unlock()
                self.delegate?.ssdpDiscovery(self, didFinishWithError: error)
            }
        }
    }

    public func stop() {
        lock.lock()
        guard _isDiscovering else {
            lock.unlock()
            return
        }
        _isDiscovering = false
        let source = readSource
        readSource = nil
        let t = timer
        timer = nil
        let fd = socketFD
        socketFD = -1
        lock.unlock()

        t?.cancel()
        if let source = source {
            source.cancel()
        } else if fd >= 0 {
            close(fd)
        }

        delegate?.ssdpDiscoveryDidFinish(self)
    }

    // MARK: - Private Socket Setup & Reading

    private func startListeningAndSendSearch(
        searchTarget: String,
        port: in_port_t,
        duration: TimeInterval
    ) throws {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOTSOCK)
        }

        // Set non-blocking mode
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        // Allow address reuse & broadcast
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var broadcast: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))
        #if os(macOS)
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))
        #endif

        // Bind to ephemeral port on any interface
        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = 0
        bindAddr.sin_addr.s_addr = INADDR_ANY.bigEndian

        let bindRes = withUnsafePointer(to: &bindAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRes == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
        }

        // Set multicast TTL
        var ttl: UInt8 = 4
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        lock.lock()
        guard _isDiscovering else {
            lock.unlock()
            close(fd)
            return
        }
        self.socketFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.readAvailableDatagrams(fd: fd)
        }
        source.setCancelHandler {
            close(fd)
        }
        self.readSource = source
        source.resume()

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + duration)
        t.setEventHandler { [weak self] in
            self?.stop()
        }
        self.timer = t
        t.resume()
        lock.unlock()

        // Construct standard UPnP M-SEARCH message
        let message = "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: 239.255.255.250:\(port)\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "MX: \(max(1, Int(duration)))\r\n" +
            "ST: \(searchTarget)\r\n\r\n"

        // Broadcast across all active IPv4 interfaces
        self.sendSearchToAllInterfaces(fd: fd, message: message, port: port)

        // Retransmit after 250ms to handle Wi-Fi multicast drop
        if duration > 0.5 {
            queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self, self.isDiscovering else { return }
                self.sendSearchToAllInterfaces(fd: fd, message: message, port: port)
            }
        }
    }

    private func sendSearchToAllInterfaces(fd: Int32, message: String, port: in_port_t) {
        var destAddr = sockaddr_in()
        destAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = in_port_t(port).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &destAddr.sin_addr)

        let interfaces = Self.activeIPv4Addresses()
        if interfaces.isEmpty {
            sendSearchDatagram(fd: fd, destAddr: &destAddr, message: message)
        } else {
            for ip in interfaces {
                var ifAddr = in_addr()
                if inet_pton(AF_INET, ip, &ifAddr) == 1 {
                    setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &ifAddr, socklen_t(MemoryLayout<in_addr>.size))
                }
                sendSearchDatagram(fd: fd, destAddr: &destAddr, message: message)
            }
        }
    }

    private func sendSearchDatagram(fd: Int32, destAddr: inout sockaddr_in, message: String) {
        message.utf8CString.withUnsafeBufferPointer { buf in
            withUnsafePointer(to: &destAddr) { saPtr in
                saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = sendto(fd, buf.baseAddress, buf.count - 1, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private static func activeIPv4Addresses() -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var addresses: [String] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(ifa.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") {
                    addresses.append(ip)
                }
            }
        }
        return addresses
    }

    private func readAvailableDatagrams(fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            var senderAddr = sockaddr_storage()
            var senderLen = socklen_t(MemoryLayout<sockaddr_storage>.size)

            let bytesRead = withUnsafeMutablePointer(to: &senderAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buffer, buffer.count, 0, sa, &senderLen)
                }
            }

            guard bytesRead > 0 else { break }

            let data = Data(buffer[0..<bytesRead])
            guard let responseStr = String(data: data, encoding: .utf8) else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let hostRes = withUnsafePointer(to: &senderAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    getnameinfo(sa, senderLen, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST)
                }
            }
            let remoteHost = hostRes == 0 ? String(cString: hostBuffer) : ""
            let service = SSDPService(host: remoteHost, response: responseStr)
            self.delegate?.ssdpDiscovery(self, didDiscoverService: service)
        }
    }
}
