//
//  WindowControl.swift
//  HyperVibe
//
//  Window-state changes on the frontmost window: full screen, minimise.
//
//  NOT by synthesizing the menu shortcut. Ctrl+Cmd+F is the shortcut every app carries for full
//  screen, and it looks like it should work, but a synthesized chord does not take effect — the
//  same wall the Space-switching hotkeys hit. What does work is the Accessibility API: a standard
//  window exposes writable `AXFullScreen` and `AXMinimized` attributes, and setting them performs
//  the real transition, animation included. Cmd+M would probably work where Ctrl+Cmd+F did not,
//  but there is no way to know which menu shortcuts are honoured without testing each one, and the
//  AX route needs no such luck.
//
//  Requires the Accessibility permission the app already needs to synthesize input at all.
//

import AppKit
import ApplicationServices

enum WindowControl {

    /// A window pinned as the arrange target. Window mode captures this ONCE when it arms, so
    /// every later arrange acts on the same window even if the mouse later sits over another app.
    struct Target {
        let app: NSRunningApplication
        let window: AXUIElement
    }

    /// Toggle the frontmost window in or out of full screen. Logs why it could not, rather than
    /// failing quietly — an unsupported window is a normal outcome worth seeing.
    static func toggle() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            rmDebug("🖥 fullscreen: no frontmost application"); return
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focused: CFTypeRef?
        let got = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focused)
        guard got == .success, let raw = focused, CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            rmDebug("🖥 fullscreen: no focused window for \(app.localizedName ?? "?") (AX \(got.rawValue))")
            return
        }
        let window = raw as! AXUIElement

        // Not every window can go full screen — a panel or a settings sheet has no such attribute.
        var settable: DarwinBoolean = false
        let can = AXUIElementIsAttributeSettable(window, attribute, &settable)
        guard can == .success, settable.boolValue else {
            rmDebug("🖥 fullscreen: \(app.localizedName ?? "?") window does not support it")
            return
        }

        var current: CFTypeRef?
        let isFull = AXUIElementCopyAttributeValue(window, attribute, &current) == .success
            && (current as? Bool ?? false)

        let result = AXUIElementSetAttributeValue(window, attribute, (!isFull) as CFBoolean)
        rmDebug("🖥 fullscreen: \(app.localizedName ?? "?") \(isFull ? "exit" : "enter")"
              + (result == .success ? "" : " FAILED (AX \(result.rawValue))"))
    }

    /// Minimise the frontmost window to the Dock.
    static func minimize() {
        guard let target = focusedWindow() else { return }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(target.window, minimizedAttribute, &settable) == .success,
              settable.boolValue else {
            rmDebug("🖥 minimize: \(target.app.localizedName ?? "?") window cannot be minimised")
            return
        }
        let result = AXUIElementSetAttributeValue(target.window, minimizedAttribute, true as CFBoolean)
        rmDebug("🖥 minimize: \(target.app.localizedName ?? "?")"
              + (result == .success ? "" : " FAILED (AX \(result.rawValue))"))
    }

    /// Close the frontmost WINDOW — literally pressing its red button, not sending Cmd+W.
    ///
    /// The difference matters in anything tabbed: Cmd+W closes the active TAB, while the red button
    /// closes the whole window. Pressing the real control is also the only way to be sure which of
    /// the two you get, since an app is free to bind Cmd+W however it likes.
    static func close() {
        guard let target = focusedWindow() else { return }
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(target.window, kAXCloseButtonAttribute as CFString,
                                            &button) == .success,
              let raw = button, CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            rmDebug("🖥 close: \(target.app.localizedName ?? "?") window has no close button")
            return
        }
        let result = AXUIElementPerformAction(raw as! AXUIElement, kAXPressAction as CFString)
        rmDebug("🖥 close: \(target.app.localizedName ?? "?")"
              + (result == .success ? "" : " FAILED (AX \(result.rawValue))"))
    }

    /// Snap the frontmost window to the left half of the screen (macOS-style tiling).
    static func snapLeft() {
        if let target = focusedWindow() { tile(fraction: 0.5, left: true, target: target) }
    }

    /// Snap the frontmost window to the right half of the screen.
    static func snapRight() {
        if let target = focusedWindow() { tile(fraction: 0.5, left: false, target: target) }
    }

    /// Maximize the frontmost window to fill the screen's visible area WITHOUT entering macOS
    /// full screen (no separate Space, Dock/menu bar stay visible).
    static func maximize() {
        guard let target = focusedWindow() else { return }
        maximize(target: target)
    }

    /// Maximize a pinned window (window mode).
    static func maximize(target: Target) {
        guard let frame = screenArea(for: target) else { return }
        setFrame(frame, target: target)
    }

    /// Restore the frontmost window to a previously captured frame (its pre-arrange geometry).
    static func restore(to frame: CGRect) {
        if let target = focusedWindow() { setFrame(frame, target: target) }
    }

    /// Restore a pinned window to its pre-arrange frame.
    static func restore(to frame: CGRect, target: Target) {
        setFrame(frame, target: target)
    }

    /// Restore the frontmost window to a centered, roughly 62%-of-screen state when no original
    /// frame was captured.
    static func restoreCentered() {
        guard let target = focusedWindow() else { return }
        restoreCentered(target: target)
    }

    /// Center a pinned window when no pre-arrange frame was captured.
    static func restoreCentered(target: Target) {
        guard let area = screenArea(for: target) else { return }
        let width = area.width * 0.62
        let height = area.height * 0.62
        setFrame(CGRect(x: area.midX - width / 2,
                        y: area.midY - height / 2,
                        width: width,
                        height: height), target: target)
    }

    /// Snap a pinned window (window mode).
    static func snapLeft(target: Target) {
        tile(fraction: 0.5, left: true, target: target)
    }

    /// Snap a pinned window (window mode).
    static func snapRight(target: Target) {
        tile(fraction: 0.5, left: false, target: target)
    }

    /// Minimize a pinned window (window mode).
    static func minimize(target: Target) {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(target.window, minimizedAttribute, &settable) == .success,
              settable.boolValue else {
            rmDebug("🖥 minimize: \(target.app.localizedName ?? "?") window cannot be minimised")
            return
        }
        let result = AXUIElementSetAttributeValue(target.window, minimizedAttribute, true as CFBoolean)
        rmDebug("🖥 minimize: \(target.app.localizedName ?? "?")"
              + (result == .success ? "" : " FAILED (AX \(result.rawValue))"))
    }

    /// Frame of a pinned window, in global Quartz coordinates (top-left origin).
    static func frame(of target: Target) -> CGRect? {
        windowFrame(target.window)
    }

    /// The window under the cursor, regardless of which app macOS considers frontmost. This is
    /// what "I selected this app" should mean in window arrange mode: the user points at a window
    /// (on whatever display), long-presses, and that window is what gets arranged — never a
    /// different app the system happens to think is active.
    static func targetUnderCursor() -> Target? {
        guard let point = CGEvent(source: nil)?.location,
              let pid = frontmostPIDUnderCursor(at: point) else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return nil }
        for window in windows {
            if let frame = windowFrame(window), frame.contains(point) {
                return Target(app: NSRunningApplication(processIdentifier: pid)!,
                              window: window)
            }
        }
        return nil
    }

    private static func windowFrame(_ window: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let pos = posValue,
              let size = sizeValue else {
            return nil
        }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else {
            return nil
        }
        return CGRect(origin: origin, size: dimensions)
    }

    /// PID of the largest layer-0 window under `point` (global Quartz coords), if any.
    private static func frontmostPIDUnderCursor(at point: CGPoint) -> pid_t? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var best: (pid: pid_t, area: Double)?
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any] else { continue }
            let rect = CGRect(x: bounds["X"] as? Double ?? 0,
                              y: bounds["Y"] as? Double ?? 0,
                              width: bounds["Width"] as? Double ?? 0,
                              height: bounds["Height"] as? Double ?? 0)
            guard rect.contains(point) else { continue }
            let area = rect.width * rect.height
            if area > (best?.area ?? 0) { best = (pid, area) }
        }
        return best?.pid
    }

    /// Bounds of the frontmost window's focused window, in global Quartz coordinates (top-left
    /// origin), or nil when the app/window does not expose a position/size.
    static func focusedWindowFrame() -> CGRect? {
        guard let target = focusedWindow() else { return nil }
        return frame(of: target)
    }

    /// The screen's visible area in global Quartz coordinates (top-left origin), for the screen
    /// the given target's window is actually on (external display aware).
    private static func screenArea(for target: Target) -> CGRect? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        var screen = NSScreen.main ?? screens[0]
        if let frame = frame(of: target) {
            // Both the window frame and CGDisplayBounds are in global Quartz coordinates
            // (top-left origin), so hit-testing is direct and cannot be fooled by a screen that
            // sits above or below the main display.
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            var ids = [CGDirectDisplayID](repeating: 0, count: 16)
            var count: UInt32 = 0
            CGGetActiveDisplayList(16, &ids, &count)
            if let displayID = ids.prefix(Int(count)).first(where: {
                CGDisplayBounds($0).contains(centre)
            }), let match = screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
            }) {
                screen = match
            }
        }

        // NSScreen frames are AppKit global (bottom-left origin); visible area needs to come back
        // to Quartz (top-left origin). Quartz y=0 is ALWAYS the top of the PRIMARY display, so the
        // conversion anchor is the primary screen's AppKit top — never the global top of all
        // screens (a display stacked above the main one would shift every coordinate by its own
        // height) and never the target screen's own top (a display below the main one would do the
        // same in the other direction).
        let vf = screen.visibleFrame                      // AppKit, bottom-left origin
        let primaryTop = NSScreen.main?.frame.maxY ?? screens.map { $0.frame.maxY }.max()!
        let areaMinY = primaryTop - vf.maxY
        rmDebug("🖥 arrange screen=\(screen.localizedName) visible=\(Int(vf.width))x\(Int(vf.height)) "
              + "at \(Int(areaMinY)),\(Int(areaMinY + vf.height))")
        return CGRect(x: vf.minX, y: areaMinY, width: vf.width, height: vf.height)
    }

    /// A half-screen tile in global Quartz coordinates (top-left origin). `left` picks which half;
    /// the other half is implied by the same width.
    private static func tileFrame(fraction: CGFloat, left: Bool, target: Target) -> CGRect? {
        guard let area = screenArea(for: target) else { return nil }
        let width = area.width * fraction
        return CGRect(x: left ? area.minX : area.maxX - width,
                      y: area.minY,
                      width: width,
                      height: area.height)
    }

    /// Exit full screen first when the window is full screen — a full-screen window has no usable
    /// position/size attributes, so setting them fails silently. Let the exit animation finish,
    /// then tile.
    private static func tile(fraction: CGFloat, left: Bool, target: Target) {
        guard let frame = tileFrame(fraction: fraction, left: left, target: target) else { return }
        let isFull = isFullscreen(target)
        if isFull {
            setFullscreen(false, target: target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                setFrame(frame, target: target)
            }
        } else {
            setFrame(frame, target: target)
        }
    }

    private static func setFrame(_ frame: CGRect, target: Target) {
        var pos = frame.origin
        var size = frame.size
        guard let posValue = AXValueCreate(.cgPoint, &pos),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        let moved = AXUIElementSetAttributeValue(target.window, kAXPositionAttribute as CFString, posValue) == .success
        let resized = AXUIElementSetAttributeValue(target.window, kAXSizeAttribute as CFString, sizeValue) == .success
        rmDebug("🖥 window: \(target.app.localizedName ?? "?") \(moved && resized ? "tiled" : "tile failed") to "
              + "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
    }

    private static func isFullscreen(_ target: Target) -> Bool {
        var current: CFTypeRef?
        guard AXUIElementCopyAttributeValue(target.window, attribute as CFString, &current) == .success,
              let value = current as? Bool else {
            return false
        }
        return value
    }

    private static func setFullscreen(_ on: Bool, target: Target) {
        let result = AXUIElementSetAttributeValue(target.window, attribute as CFString, on as CFBoolean)
        rmDebug("🖥 fullscreen: \(target.app.localizedName ?? "?") \(on ? "enter" : "exit")"
              + (result == .success ? "" : " FAILED (AX \(result.rawValue))"))
    }

    /// The frontmost app and its focused window, or nil with a reason logged.
    static func focusedWindow() -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            rmDebug("🖥 window: no frontmost application"); return nil
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        let got = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focused)
        guard got == .success, let raw = focused, CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            rmDebug("🖥 window: no focused window for \(app.localizedName ?? "?") (AX \(got.rawValue))")
            return nil
        }
        return Target(app: app, window: (raw as! AXUIElement))
    }

    /// Neither is exposed as a public constant by ApplicationServices; both are documented names.
    private static let attribute = "AXFullScreen" as CFString
    private static let minimizedAttribute = "AXMinimized" as CFString
}
