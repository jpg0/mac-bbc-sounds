import XCTest
@testable import BBCSoundsMenuBar

final class NetworkUtilitiesTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        NetworkUtilities.customIPv4Resolver = nil
    }

    func testPrimaryIPv4AddressFormat() {
        let ip = NetworkUtilities.primaryIPv4Address()
        // On a connected machine (e.g. Wi-Fi / Ethernet), ip should be resolved
        if let ip = ip {
            let parts = ip.split(separator: ".")
            XCTAssertEqual(parts.count, 4, "IPv4 address must have 4 octets: \(ip)")
            for part in parts {
                guard let val = Int(part) else {
                    XCTFail("Octet \(part) is not a valid integer in \(ip)")
                    return
                }
                XCTAssertTrue((0...255).contains(val), "Octet \(val) must be between 0 and 255 in \(ip)")
            }
            XCTAssertFalse(ip.hasPrefix("127."), "Should not return loopback address: \(ip)")
            XCTAssertFalse(ip.hasPrefix("169.254."), "Should not return link-local address: \(ip)")
        }
    }

    func testCustomIPv4ResolverOverride() {
        NetworkUtilities.customIPv4Resolver = { "10.0.0.42" }
        XCTAssertEqual(NetworkUtilities.primaryIPv4Address(), "10.0.0.42")

        NetworkUtilities.customIPv4Resolver = nil
        // After clearing, it should either return system IP or nil
        let sysIP = NetworkUtilities.primaryIPv4Address()
        XCTAssertNotEqual(sysIP, "10.0.0.42")
    }
}
