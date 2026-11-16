//
//  MicrophoneRouter.swift
//  leanring-buddy
//
//  Picks which microphone Thambi listens with, and falls back to the Mac's own microphone when
//  the chosen one fails.
//
//  Why this matters with Bluetooth headphones: the moment an app opens a Bluetooth headset's
//  microphone, macOS switches the headset to "call" mode and everything you hear turns thin and
//  quiet. Listening with the Mac's built-in microphone instead keeps the headphones in their
//  normal high-quality mode, so Thambi's voice (and your music) still sounds right.
//
//  Nothing here records anything; it only reads the list of audio devices and chooses one.
//

import AVFoundation
import CoreAudio
import Foundation

enum MicrophoneChoice: String, CaseIterable, Identifiable {
    /// The Mac's own microphone whenever the system microphone is a Bluetooth headset; otherwise the system one.
    case automatic
    /// Always whatever is chosen in System Settings > Sound > Input.
    case systemDefault

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .automatic: return "Automatic"
        case .systemDefault: return "System input"
        }
    }

    private static let defaultsKey = "microphoneChoice"

    static var current: MicrophoneChoice {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(MicrophoneChoice.init(rawValue:)) ?? .automatic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

enum MicrophoneRouter {

    struct InputDevice: Equatable {
        let deviceID: AudioDeviceID
        let name: String
        let isBuiltIn: Bool
        let isBluetooth: Bool
    }

    // MARK: - Choosing

    /// The pure decision, so it can be unit-tested: which device to listen with.
    /// Nil means "leave the engine on the system default".
    static func preferredDevice(
        choice: MicrophoneChoice,
        systemDefault: InputDevice?,
        builtIn: InputDevice?,
        mustAvoidSystemDefault: Bool
    ) -> InputDevice? {
        if mustAvoidSystemDefault {
            // The system microphone just failed: use the Mac's own, if it is a different device.
            guard let builtIn, builtIn.deviceID != systemDefault?.deviceID else { return nil }
            return builtIn
        }
        guard choice == .automatic, let systemDefault, systemDefault.isBluetooth, let builtIn else { return nil }
        return builtIn
    }

    /// Points the engine's microphone at the right device for this recording.
    /// Returns a short description for the log ("MacBook Pro Microphone (built-in, instead of AirPods)").
    @discardableResult
    static func route(_ audioEngine: AVAudioEngine, avoidingSystemDefault mustAvoidSystemDefault: Bool) -> String {
        let systemDefault = systemDefaultInputDevice()
        let chosen = preferredDevice(
            choice: MicrophoneChoice.current,
            systemDefault: systemDefault,
            builtIn: builtInInputDevice(),
            mustAvoidSystemDefault: mustAvoidSystemDefault
        )
        let target = chosen ?? systemDefault
        guard let target else { return "no microphone found" }
        setInputDevice(target.deviceID, on: audioEngine)
        if let chosen, chosen.deviceID != systemDefault?.deviceID {
            return "\(chosen.name) (instead of \(systemDefault?.name ?? "the system input"))"
        }
        return target.name
    }

    /// True when a different microphone is available to fall back to.
    static var hasFallbackMicrophone: Bool {
        guard let builtIn = builtInInputDevice() else { return false }
        return builtIn.deviceID != systemDefaultInputDevice()?.deviceID
    }

    // MARK: - Core Audio

    private static func setInputDevice(_ deviceID: AudioDeviceID, on audioEngine: AVAudioEngine) {
        guard let audioUnit = audioEngine.inputNode.audioUnit else { return }
        var mutableDeviceID = deviceID
        AudioUnitSetProperty(
            audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &mutableDeviceID, UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    static func systemDefaultInputDevice() -> InputDevice? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0 else { return nil }
        return inputDevice(for: deviceID)
    }

    static func builtInInputDevice() -> InputDevice? {
        allInputDevices().first(where: \.isBuiltIn)
    }

    static func allInputDevices() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr else { return [] }
        return deviceIDs.compactMap(inputDevice(for:))
    }

    /// Nil when the device has no microphone.
    private static func inputDevice(for deviceID: AudioDeviceID) -> InputDevice? {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamsSize = UInt32(0)
        guard AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return nil }

        var transportType = UInt32(0)
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &transportSize, &transportType)

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let nameStatus = withUnsafeMutablePointer(to: &unmanagedName) { namePointer in
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, namePointer)
        }
        let name = (nameStatus == noErr ? unmanagedName?.takeRetainedValue() as String? : nil) ?? "Microphone"

        return InputDevice(
            deviceID: deviceID,
            name: name,
            isBuiltIn: transportType == kAudioDeviceTransportTypeBuiltIn,
            isBluetooth: transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE
        )
    }
}
