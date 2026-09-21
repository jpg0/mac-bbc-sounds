import Foundation

/// Active audio output routing destination.
public enum AudioOutputTarget: Equatable, Hashable, Identifiable, Sendable {
    case thisMac
    case sonos(SonosDevice)

    public var id: String {
        switch self {
        case .thisMac:
            return "thisMac"
        case .sonos(let device):
            return "sonos-\(device.id)"
        }
    }

    public var displayName: String {
        switch self {
        case .thisMac:
            return "This Mac"
        case .sonos(let device):
            return device.displayName
        }
    }

    public var isMac: Bool {
        if case .thisMac = self { return true }
        return false
    }

    public var isSonos: Bool {
        if case .sonos = self { return true }
        return false
    }

    public var sonosDevice: SonosDevice? {
        if case .sonos(let device) = self { return device }
        return nil
    }
}
