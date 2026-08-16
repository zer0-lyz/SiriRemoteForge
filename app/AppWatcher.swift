//
//  AppWatcher.swift
//  HyperVibe (config engine integration)
//
//  Tracks the frontmost application and reports its bundle identifier so the
//  config engine can switch modes per-app.
//

import AppKit
import ApplicationServices
import CoreGraphics

final class AppWatcher {
    /// Site markers per video client, used to tell a playback window ("剧名-腾讯视频") from the
    /// app's own chrome ("腾讯视频"). A window whose title contains a site marker AND other
    /// content is a playback page; the profile key then gets a `:playing` suffix.
    private static let videoSiteMarkers: [String: [String]] = [
        "com.tencent.tenvideo": ["腾讯视频", "v.qq.com"],
        "com.youku.mac": ["优酷", "youku"],
        "com.bilibili.bilibiliPC": ["哔哩哔哩", "bilibili", "b23.tv"],
    ]

    private let onChange: (String) -> Void
    private var token: NSObjectProtocol?
    private var timer: Timer?
    private var lastProfileKey: String?

    init(onChange: @escaping (String) -> Void) {
        self.onChange = onChange
        publish(NSWorkspace.shared.frontmostApplication)
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.publish(app)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.publish(NSWorkspace.shared.frontmostApplication)
        }
    }

    deinit {
        if let token = token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        timer?.invalidate()
    }

    static func profileKey(for app: NSRunningApplication?) -> String? {
        profileInfo(for: app)?.key
    }

    private func publish(_ app: NSRunningApplication?) {
        guard let info = Self.profileInfo(for: app), info.key != lastProfileKey else { return }
        if info.bundleID == "com.kingsoft.wpsoffice.mac" {
            rmDebug("🧭 WPS profile title[\(info.titleSource ?? "none")]=\(info.title ?? "nil") → \(info.key)")
        }
        let key = info.key
        lastProfileKey = key
        onChange(key)
    }

    private static func profileInfo(for app: NSRunningApplication?) -> ProfileInfo? {
        guard let app, let id = app.bundleIdentifier else { return nil }
        if videoSiteMarkers[id] != nil {
            let titleProbe = frontWindowTitle(pid: app.processIdentifier)
            let key = id + videoPlaybackSuffix(id: id, title: titleProbe.title)
            rmDebug("🧭 video profile title=\(titleProbe.title ?? "nil") → \(key)")
            return ProfileInfo(bundleID: id, key: key, title: titleProbe.title,
                               titleSource: titleProbe.source)
        }
        guard id == "com.kingsoft.wpsoffice.mac" else {
            return ProfileInfo(bundleID: id, key: id, title: nil, titleSource: nil)
        }
        let titleProbe = frontWindowTitle(pid: app.processIdentifier)
        let title = titleProbe.title
        let key: String
        if title?.matchesFileExtension(["doc", "docx", "wps", "rtf", "txt"]) == true {
            key = "\(id):writer"
        } else if title?.matchesFileExtension(["xls", "xlsx", "xlsm", "csv", "et", "ett"]) == true {
            key = "\(id):sheet"
        } else if title?.matchesFileExtension(["ppt", "pptx", "dps", "dpt"]) == true {
            key = "\(id):presentation"
        } else {
            key = id
        }
        return ProfileInfo(bundleID: id, key: key, title: title, titleSource: titleProbe.source)
    }

    /// ":playing" when the window title is a video page (site marker plus a real title), "" when it
    /// is the app's own chrome/list page.
    private static func videoPlaybackSuffix(id: String, title: String?) -> String {
        guard let title, let markers = videoSiteMarkers[id] else { return "" }
        let lower = title.lowercased()
        guard markers.contains(where: { lower.contains($0.lowercased()) }) else { return "" }
        var rest = title
        for marker in markers {
            rest = rest.replacingOccurrences(of: marker, with: " ", options: .caseInsensitive)
        }
        let meaningful = rest
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isWhitespace }
        return meaningful.count >= 2 ? ":playing" : ""
    }

    private static func frontWindowTitle(pid: pid_t) -> (title: String?, source: String?) {
        if let title = frontWindowTitleFromCGWindowList(pid: pid) {
            return (title, "cgwindow")
        }
        if let title = frontWindowTitleFromAccessibility(pid: pid) {
            return (title, "accessibility")
        }
        return (nil, nil)
    }

    private static func frontWindowTitleFromCGWindowList(pid: pid_t) -> String? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let candidates = windows.compactMap { window -> (order: Int, title: String, area: Double)? in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let title = window[kCGWindowName as String] as? String,
                  !title.isEmpty,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any] else {
                return nil
            }
            let width = bounds["Width"] as? Double ?? 0
            let height = bounds["Height"] as? Double ?? 0
            let number = window[kCGWindowNumber as String] as? Int ?? Int.max
            return (number, title, width * height)
        }
        return candidates.sorted {
            if abs($0.area - $1.area) > 10 { return $0.area > $1.area }
            return $0.order < $1.order
        }.first?.title
    }

    private static func frontWindowTitleFromAccessibility(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
              let window = focusedWindow else {
            return nil
        }
        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue((window as! AXUIElement), kAXTitleAttribute as CFString, &titleValue) == .success,
              let title = titleValue as? String,
              !title.isEmpty else {
            return nil
        }
        return title
    }
}

private struct ProfileInfo {
    let bundleID: String
    let key: String
    let title: String?
    let titleSource: String?
}

private extension String {
    func matchesFileExtension(_ extensions: [String]) -> Bool {
        let lowercasedTitle = lowercased()
        return extensions.contains { ext in
            guard let range = lowercasedTitle.range(of: ".\(ext)") else { return false }
            let after = range.upperBound
            guard after < lowercasedTitle.endIndex else { return true }
            let next = lowercasedTitle[after]
            return !next.isLetter && !next.isNumber
        }
    }
}
