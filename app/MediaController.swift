//
//  MediaController.swift
//  Remotastic
//
//  Sends system media key events (NX_SYSDEFINED subtype 8) for remote button mappings.
//

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import CoreAudio
import Darwin

class MediaController {

    static let shared = MediaController()

    func sendMediaKey(_ keyType: MediaKeyInterceptor.MediaKeyType) {
        guard let nxCode = nxKeyCode(for: keyType) else { return }
        postSystemDefinedKey(nxKeyCode: nxCode)
    }

    /// Current mute state of the default output device, or nil when the device does not expose it.
    static func defaultOutputMuted() -> Bool? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &muted) == noErr else {
            return nil
        }
        return muted != 0
    }

    /// Set the mute state of the default output device. Returns false when unsupported.
    @discardableResult
    static func setDefaultOutputMuted(_ muted: Bool) -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(
            deviceID, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr else {
            return nil
        }
        return deviceID
    }

    private func nxKeyCode(for keyType: MediaKeyInterceptor.MediaKeyType) -> Int32? {
        switch keyType {
        case .playPause: return NX_KEYTYPE_PLAY
        case .next: return NX_KEYTYPE_NEXT
        case .previous: return NX_KEYTYPE_PREVIOUS
        case .volumeUp: return NX_KEYTYPE_SOUND_UP
        case .volumeDown: return NX_KEYTYPE_SOUND_DOWN
        case .mute: return NX_KEYTYPE_MUTE
        }
    }

    private func postSystemDefinedKey(nxKeyCode: Int32) {
        let ts = ProcessInfo.processInfo.systemUptime
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: ts,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((nxKeyCode << 16) | (0xa << 8)),
            data2: -1
        )
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xb00),
            timestamp: ts,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((nxKeyCode << 16) | (0xb << 8)),
            data2: -1
        )
        let sessionTap: CGEventTapLocation = .cgSessionEventTap
        keyDown?.cgEvent?.post(tap: sessionTap)
        // Schedule the key-up rather than usleep()ing for it. This runs on the main thread, which
        // also services the CGEventTap and every HID callback — blocking it for 50ms per press adds
        // up and is exactly the kind of stall that gets the tap disabled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            keyUp?.cgEvent?.post(tap: sessionTap)
        }
    }
}
