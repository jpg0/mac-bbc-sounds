import Foundation
import CoreAudio
import AudioToolbox

/// Protocol defining the interface for monitoring and controlling the Mac's system audio volume and mute state.
public protocol SystemAudioServiceProtocol: AnyObject, Sendable {
    /// Callback triggered when the user modifies system output volume (e.g. keyboard keys F11/F12, Control Center).
    var onVolumeChanged: (@Sendable (Float) -> Void)? { get set }

    /// Callback triggered when the user modifies system mute state (e.g. keyboard key F10).
    var onMuteChanged: (@Sendable (Bool) -> Void)? { get set }

    /// Reads current system output volume (0.0 ... 1.0).
    func getVolume() -> Float?

    /// Reads current system output mute state.
    func getMute() -> Bool?

    /// Sets the Mac system output volume (0.0 ... 1.0).
    /// - Parameters:
    ///   - volume: Scalar volume between 0.0 and 1.0.
    ///   - silently: If true, listener callbacks will not be triggered.
    func setVolume(_ volume: Float, silently: Bool)

    /// Sets the Mac system output mute state.
    /// - Parameters:
    ///   - isMuted: Boolean mute state.
    ///   - silently: If true, listener callbacks will not be triggered.
    func setMute(_ isMuted: Bool, silently: Bool)

    /// Starts monitoring CoreAudio hardware property changes on the default output device.
    func startMonitoring()

    /// Stops monitoring CoreAudio hardware property changes.
    func stopMonitoring()
}

/// CoreAudio-based implementation that observes and adjusts the default macOS output device.
public final class SystemAudioService: @unchecked Sendable, SystemAudioServiceProtocol {

    public var onVolumeChanged: (@Sendable (Float) -> Void)?
    public var onMuteChanged: (@Sendable (Bool) -> Void)?

    private let queue = DispatchQueue(label: "com.trillica.SystemAudioService", qos: .userInitiated)
    private let lock = NSLock()

    private var activeDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var isMonitoring: Bool = false
    private var isSilentlyUpdating: Bool = false
    private var lastKnownVolume: Float = -1.0
    private var lastKnownMute: Bool = false

    // Retained blocks for unregistering CoreAudio property listeners
    private var deviceChangeListenerBlock: AudioObjectPropertyListenerBlock?
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?

    public init() {}

    deinit {
        stopMonitoring()
    }

    public func startMonitoring() {
        lock.withLock {
            guard !isMonitoring else { return }
            isMonitoring = true
        }

        setupDefaultDeviceListener()
        bindToCurrentDefaultOutputDevice()
    }

    public func stopMonitoring() {
        lock.withLock {
            guard isMonitoring else { return }
            isMonitoring = false
        }

        removeDeviceListener()
        removeActiveDeviceListeners()
    }

    // MARK: - Device Resolution

    private func defaultOutputDeviceID() -> AudioObjectID? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }

    private func bindToCurrentDefaultOutputDevice() {
        guard let deviceID = defaultOutputDeviceID() else { return }
        lock.withLock {
            self.activeDeviceID = deviceID
            if let vol = readVolume(for: deviceID) {
                self.lastKnownVolume = vol
            }
            if let mute = readMute(for: deviceID) {
                self.lastKnownMute = mute
            }
        }
        attachListeners(to: deviceID)
    }

    // MARK: - CoreAudio Property Addresses

    private func volumeAddress(for deviceID: AudioObjectID) -> AudioObjectPropertyAddress {
        var virtualAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &virtualAddress) {
            return virtualAddress
        }

        return AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func defaultDeviceAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    // MARK: - Getters

    public func getVolume() -> Float? {
        let devID: AudioObjectID = lock.withLock {
            activeDeviceID != kAudioObjectUnknown ? activeDeviceID : (defaultOutputDeviceID() ?? AudioObjectID(kAudioObjectUnknown))
        }
        guard devID != kAudioObjectUnknown else { return nil }
        return readVolume(for: devID)
    }

    public func getMute() -> Bool? {
        let devID: AudioObjectID = lock.withLock {
            activeDeviceID != kAudioObjectUnknown ? activeDeviceID : (defaultOutputDeviceID() ?? AudioObjectID(kAudioObjectUnknown))
        }
        guard devID != kAudioObjectUnknown else { return nil }
        return readMute(for: devID)
    }

    private func readVolume(for deviceID: AudioObjectID) -> Float? {
        var address = volumeAddress(for: deviceID)
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &volume
        )

        guard status == noErr else { return nil }
        return Float(volume)
    }

    private func readMute(for deviceID: AudioObjectID) -> Bool? {
        var address = muteAddress()
        var isMuted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &isMuted
        )

        guard status == noErr else { return nil }
        return isMuted != 0
    }

    // MARK: - Setters

    public func setVolume(_ volume: Float, silently: Bool) {
        let clamped = max(0.0, min(1.0, volume))
        let devID: AudioObjectID = lock.withLock {
            if silently {
                self.isSilentlyUpdating = true
            }
            self.lastKnownVolume = clamped
            return activeDeviceID != kAudioObjectUnknown ? activeDeviceID : (defaultOutputDeviceID() ?? AudioObjectID(kAudioObjectUnknown))
        }

        guard devID != kAudioObjectUnknown else {
            if silently {
                lock.withLock { self.isSilentlyUpdating = false }
            }
            return
        }

        var address = volumeAddress(for: devID)
        var vol = Float32(clamped)
        let size = UInt32(MemoryLayout<Float32>.size)

        _ = AudioObjectSetPropertyData(
            devID,
            &address,
            0,
            nil,
            size,
            &vol
        )

        if silently {
            queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.lock.withLock {
                    self?.isSilentlyUpdating = false
                }
            }
        }
    }

    public func setMute(_ isMuted: Bool, silently: Bool) {
        let devID: AudioObjectID = lock.withLock {
            if silently {
                self.isSilentlyUpdating = true
            }
            self.lastKnownMute = isMuted
            return activeDeviceID != kAudioObjectUnknown ? activeDeviceID : (defaultOutputDeviceID() ?? AudioObjectID(kAudioObjectUnknown))
        }

        guard devID != kAudioObjectUnknown else {
            if silently {
                lock.withLock { self.isSilentlyUpdating = false }
            }
            return
        }

        var address = muteAddress()
        var muteVal: UInt32 = isMuted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)

        _ = AudioObjectSetPropertyData(
            devID,
            &address,
            0,
            nil,
            size,
            &muteVal
        )

        if silently {
            queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.lock.withLock {
                    self?.isSilentlyUpdating = false
                }
            }
        }
    }

    // MARK: - Listener Management

    private func setupDefaultDeviceListener() {
        var address = defaultDeviceAddress()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDefaultDeviceChanged()
        }
        self.deviceChangeListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            block
        )
    }

    private func removeDeviceListener() {
        guard let block = deviceChangeListenerBlock else { return }
        var address = defaultDeviceAddress()
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            block
        )
        self.deviceChangeListenerBlock = nil
    }

    private func handleDefaultDeviceChanged() {
        removeActiveDeviceListeners()
        bindToCurrentDefaultOutputDevice()
    }

    private func attachListeners(to deviceID: AudioObjectID) {
        var volAddress = volumeAddress(for: deviceID)
        let volBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleVolumeChanged(on: deviceID)
        }
        self.volumeListenerBlock = volBlock

        AudioObjectAddPropertyListenerBlock(
            deviceID,
            &volAddress,
            queue,
            volBlock
        )

        var muteAddr = muteAddress()
        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleMuteChanged(on: deviceID)
        }
        self.muteListenerBlock = muteBlock

        AudioObjectAddPropertyListenerBlock(
            deviceID,
            &muteAddr,
            queue,
            muteBlock
        )
    }

    private func removeActiveDeviceListeners() {
        let devID = lock.withLock { self.activeDeviceID }
        guard devID != kAudioObjectUnknown else { return }

        if let volBlock = volumeListenerBlock {
            var volAddress = volumeAddress(for: devID)
            AudioObjectRemovePropertyListenerBlock(devID, &volAddress, queue, volBlock)
            self.volumeListenerBlock = nil
        }

        if let muteBlock = muteListenerBlock {
            var muteAddr = muteAddress()
            AudioObjectRemovePropertyListenerBlock(devID, &muteAddr, queue, muteBlock)
            self.muteListenerBlock = nil
        }
    }

    private func handleVolumeChanged(on deviceID: AudioObjectID) {
        let (silently, prevVol) = lock.withLock { (isSilentlyUpdating, lastKnownVolume) }
        guard !silently else { return }

        guard let newVol = readVolume(for: deviceID) else { return }
        guard abs(newVol - prevVol) > 0.005 else { return }

        lock.withLock {
            self.lastKnownVolume = newVol
        }

        onVolumeChanged?(newVol)
    }

    private func handleMuteChanged(on deviceID: AudioObjectID) {
        let (silently, prevMute) = lock.withLock { (isSilentlyUpdating, lastKnownMute) }
        guard !silently else { return }

        guard let newMute = readMute(for: deviceID) else { return }
        guard newMute != prevMute else { return }

        lock.withLock {
            self.lastKnownMute = newMute
        }

        onMuteChanged?(newMute)
    }
}
