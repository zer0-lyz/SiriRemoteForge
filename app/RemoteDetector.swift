//
//  RemoteDetector.swift
//  HyperVibe
//
//  Detects Siri Remote via IOKit HID
//

import Foundation
import IOKit
import IOKit.hid

/// Append diagnostic line to /tmp/hypervibe.log (unified-log redacts NSLog under hardened runtime).
func rmDebug(_ msg: String) {
    let line = "\(Date()) \(msg)\n"
    if let data = line.data(using: .utf8) {
        let path = "/tmp/hypervibe.log"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

class RemoteDetector {
    private var manager: IOHIDManager?
    private var deviceCallback: ((IOHIDDevice?) -> Void)?
    private var currentDevice: IOHIDDevice?
    // A Siri Remote exposes several HID interfaces with the same vendor/product pair. Track the
    // interfaces themselves so one transient interface removal cannot tear down the other inputs.
    private var activeDevices: Set<IOHIDDevice> = []
    private var activeInterfaceCounts: [String: Int] = [:]
    private let processingQueue = DispatchQueue(label: "com.hypervibe.deviceProcessing")
    
    private let appleVendorID: Int = 0x004C
    
    // Known Siri Remote / Apple TV Remote product IDs
    private let knownProductIDs: [Int] = [
        0x0221, 0x0255, 0x0266, 0x0267, 0x0269,
        0x0C4E, 0x0C4F, 0x030D, 0x030E,
        0x0315  // 3rd-gen Siri Remote (A2843, USB-C). HID name is the serial number,
                // not "Siri Remote", so it must be matched by product ID here.
    ]
    
    init(deviceCallback: @escaping (IOHIDDevice?) -> Void) {
        self.deviceCallback = deviceCallback
    }
    
    func startDetection() {
        rmDebug(String(format: "🛰 starting HID detection (vendor=0x%X)", appleVendorID))
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = manager else {
            rmDebug("⚠️ IOHIDManagerCreate returned nil")
            return
        }

        // SiriMote uses IOHIDManagerSetDeviceMatchingMultiple with per-interface dicts.
        // The Siri Remote A1513 exposes 3 HID interfaces (consumer, game controls, vendor),
        // and the singular variant with vendor-only matching does not enumerate them on
        // recent macOS BLE HID stacks.
        var matchingDicts: [[String: Any]] = [
            [kIOHIDVendorIDKey: appleVendorID, kIOHIDPrimaryUsagePageKey: 0x0C],   // Consumer Page
            [kIOHIDVendorIDKey: appleVendorID, kIOHIDPrimaryUsagePageKey: 0x0D],   // Digitizer / Game Controls
            [kIOHIDVendorIDKey: appleVendorID, kIOHIDPrimaryUsagePageKey: 0xFF00], // Apple vendor-defined
            [kIOHIDVendorIDKey: appleVendorID, kIOHIDPrimaryUsagePageKey: 0x01],   // Generic Desktop (kept for keyboards/trackpads)
        ]
        // Gen-3 exposes two additional HID-over-GATT report characteristics as usage-page 0x20
        // interfaces (AppleEmbeddedBluetoothInfrared / AppleEmbeddedBluetoothRadio). They are not
        // needed for normal button/cursor operation, so only seize them during microphone/report
        // diagnostics. The gen-3 protocol requires the 0xAF input-enable byte on every writable
        // non-Input report; omitting these interfaces made the first activation probe incomplete.
        //
        // Seizing them in normal mode was tried as a way to stop macOS seeing the Power button and
        // did NOT work — loginwindow still received it — so it is not worth occupying the IR/radio
        // interfaces. The power-button sleep is handled by the loginwindow preference instead.
        if CommandLine.arguments.contains("--dump-reports") ||
           CommandLine.arguments.contains("--capture-mic") ||
           CommandLine.arguments.contains("--activate-mic") ||
           CommandLine.arguments.contains("--native-ptt") ||
           CommandLine.arguments.contains("--direct-ptt") {
            matchingDicts.append([
                kIOHIDVendorIDKey: appleVendorID,
                kIOHIDPrimaryUsagePageKey: 0x20,
            ])
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDicts as CFArray)

        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceAddedCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, Unmanaged.passUnretained(self).toOpaque())

        // Explicitly request Input Monitoring access. IOHIDManagerOpen alone can fail with
        // kIOReturnNotPermitted (0xE00002E2) WITHOUT surfacing a prompt — especially when launched
        // as a signed .app — so ask first: this triggers the macOS prompt when the state is
        // undetermined, and tells us clearly when it's denied.
        if #available(macOS 10.15, *) {
            let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            rmDebug("🔐 Input Monitoring access: " + (granted
                ? "granted"
                : "NOT granted — enable HyperVibe in System Settings → Privacy & Security → Input Monitoring, then relaunch"))
        }

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            rmDebug(String(format: "⚠️ IOHIDManagerOpen failed (IOReturn=0x%X) — likely Input Monitoring not granted", openResult))
            return
        }
        rmDebug("🛰 IOHIDManagerOpen success")

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.enumerateAllDevices()
        }
    }
    
    func stopDetection() {
        if let manager = manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
        }
        currentDevice = nil
        processingQueue.sync {
            activeDevices.removeAll()
            activeInterfaceCounts.removeAll()
        }
        deviceCallback?(nil)
    }
    
    private func enumerateAllDevices() {
        guard let manager = manager,
              let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            rmDebug("🛰 IOHIDManagerCopyDevices returned nil/empty (TCC block or matching mismatch)")
            return
        }
        rmDebug("🛰 enumeration found \(deviceSet.count) HID device(s) matching filter")
        for device in deviceSet {
            let v = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? -1
            let p = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? -1
            let n = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
            let pup = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? -1
            let pu  = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? -1
            rmDebug(String(format: "🛰 candidate vendor=0x%X product=0x%X usagePage=0x%X usage=0x%X name=%@",
                           v, p, pup, pu, n))
            if isSiriRemote(device) {
                handleDeviceAdded(device)
            }
        }
    }
    
    private func isSiriRemote(_ device: IOHIDDevice) -> Bool {
        guard let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
              vendorID == appleVendorID else { return false }
        
        if let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
           knownProductIDs.contains(productID) {
            return true
        }
        
        if let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
            let name = productName.lowercased()
            return name.contains("remote") || name.contains("siri") || name.contains("apple tv")
        }
        
        return false
    }
    
    func handleDeviceAdded(_ device: IOHIDDevice) {
        guard isSiriRemote(device) else { return }
        
        // Get device properties (safe to read from any thread)
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        
        // Create a key based on vendor+product to group all HID interfaces from the same physical device
        // A single Siri Remote may expose multiple HID interfaces (buttons, touch, etc.)
        // but they all share the same vendor and product ID
        let deviceKey = "\(vendorID):\(productID)"
        
        // Use a serialized queue to prevent races between interface callbacks.
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            // Matching callbacks and the initial enumeration can report the same interface twice.
            // Passing it through once is enough; RemoteInputHandler also de-duplicates defensively.
            guard self.activeDevices.insert(device).inserted else { return }

            let interfaceCount = (self.activeInterfaceCounts[deviceKey] ?? 0) + 1
            self.activeInterfaceCounts[deviceKey] = interfaceCount
            let becameConnected = interfaceCount == 1
            self.currentDevice = device

            if becameConnected {
                let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
                print("✅ Siri Remote connected: \(productName) (Vendor: 0x\(String(vendorID, radix: 16, uppercase: true)), Product: 0x\(String(productID, radix: 16, uppercase: true)))")
            }

            rmDebug(String(format: "🛰 HID interface added usage=0x%X/0x%X active=%d physicalInterfaces=%d",
                           IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? -1,
                           IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? -1,
                           self.activeDevices.count, interfaceCount))
            DispatchQueue.main.async {
                self.deviceCallback?(device)
            }
        }
    }
    
    func handleDeviceRemoved(_ device: IOHIDDevice) {
        guard isSiriRemote(device) else { return }
        
        // Get device properties (safe to read from any thread)
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        
        // Create the same key based on vendor+product
        let deviceKey = "\(vendorID):\(productID)"
        
        // Use a serialized queue to prevent race conditions
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // A physical remote publishes multiple interfaces. Remove only this interface and keep
            // the handler alive while any sibling interface remains attached.
            guard self.activeDevices.remove(device) != nil else { return }

            let remainingForPhysical = max(0, (self.activeInterfaceCounts[deviceKey] ?? 1) - 1)
            if remainingForPhysical == 0 {
                self.activeInterfaceCounts.removeValue(forKey: deviceKey)
            } else {
                self.activeInterfaceCounts[deviceKey] = remainingForPhysical
            }

            rmDebug(String(format: "🛰 HID interface removed usage=0x%X/0x%X active=%d physicalInterfaces=%d",
                           IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? -1,
                           IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? -1,
                           self.activeDevices.count, remainingForPhysical))

            if self.activeDevices.isEmpty {
                let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
                print("❌ Siri Remote disconnected: \(productName)")
                self.currentDevice = nil
                DispatchQueue.main.async {
                    self.deviceCallback?(nil)
                }
            }
        }
    }
}

// C callbacks
private func deviceAddedCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context = context else { return }
    let detector = Unmanaged<RemoteDetector>.fromOpaque(context).takeUnretainedValue()
    detector.handleDeviceAdded(device)
}

private func deviceRemovedCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context = context else { return }
    let detector = Unmanaged<RemoteDetector>.fromOpaque(context).takeUnretainedValue()
    detector.handleDeviceRemoved(device)
}
