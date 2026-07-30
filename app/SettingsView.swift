//
//  SettingsView.swift
//  HyperVibe (settings UI)
//
//  Minimal, Apple-style settings window. Every value applies live and persists.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    /// Owned by the model (see `SettingsModel.device`) so the window controller drives its polling.
    @ObservedObject var device: DeviceInfo

    init(model: SettingsModel) {
        self.model = model
        self.device = model.device
    }

    /// Mirrors the real SMAppService registration — never assume the toggle succeeded.
    @State private var launchAtLogin = LaunchAtLogin.state.isOn
    @State private var launchAtLoginError: String?

    private enum Tab: String, CaseIterable { case tuning = "调校", layout = "布局" }
    @State private var tab: Tab = .tuning

    var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker
            Divider()
            switch tab {
            case .tuning:
                Form {
                    deviceSection
                    cursorSection
                    accelerationSection
                    clickSection
                    circularSection
                    buttonsSection
                    startupSection
                    footerSection
                }
                .formStyle(.grouped)
            case .layout:
                if let config = model.config {
                    LayoutView(config: config, onSave: { newConfig in
                        // Atomic, validated write → hot-reloads → refreshes model.config. A failed
                        // write (invalid config / permissions) leaves the old file intact; log it.
                        do { try ConfigStore.save(newConfig) }
                        catch { NSLog("[siriRemote] config save failed: \(error)") }
                    })
                } else {
                    Spacer()
                    Text("正在加载配置…").foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        // Flexible height (not fixed) so the window can be shrunk to fit smaller displays — the
        // inner ScrollView/Form then scroll instead of the content being clipped.
        .frame(width: tab == .layout ? 900 : 452)
        .frame(minHeight: 480, idealHeight: 900, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: tab)
        // Polling start/stop lives in SettingsWindowController — `.onDisappear` never fires for
        // this window (it is cached and only ordered out). Refresh on appear so reopening shows
        // current values immediately, and re-read the login-item registration, which the user may
        // have changed in System Settings → Login Items while the window was closed.
        .onAppear {
            device.refresh()
            launchAtLogin = LaunchAtLogin.state.isOn
        }
        // The remote can connect/disconnect while the window is open; refresh so battery and the
        // interface map do not go stale.
        .onChange(of: model.connected) { _ in device.refresh() }
    }

    // MARK: - Tab switcher

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 22).padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.68)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "appletvremote.gen4.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                )
                .shadow(color: Color.accentColor.opacity(0.35), radius: 7, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Siri 遥控器").font(.system(size: 19, weight: .semibold))
                Text("触控与手势调校")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(.bar)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.connected ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 7, height: 7)
            Text(model.connected ? "已连接" : "等待连接")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            if model.connected, let pct = device.battery {
                Divider().frame(height: 9)
                Image(systemName: batterySymbol(pct))
                    .font(.system(size: 11))
                    .foregroundStyle(batteryTint(pct))
                Text("\(pct)%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(.quaternary))
        .animation(.easeInOut(duration: 0.2), value: device.battery)
    }

    private func batterySymbol(_ pct: Int) -> String {
        switch pct {
        case ..<13:  return "battery.0percent"
        case ..<38:  return "battery.25percent"
        case ..<63:  return "battery.50percent"
        case ..<88:  return "battery.75percent"
        default:     return "battery.100percent"
        }
    }

    private func batteryTint(_ pct: Int) -> Color {
        pct < 20 ? .red : (pct < 40 ? .orange : .secondary)
    }

    // MARK: - Device

    private var deviceSection: some View {
        Section {
            if model.connected {
                if let pct = device.battery {
                    LabeledContent {
                        HStack(spacing: 6) {
                            Image(systemName: batterySymbol(pct)).foregroundStyle(batteryTint(pct))
                            Text("\(pct)%").monospacedDigit()
                        }
                    } label: { rowLabel("电量", "bolt.fill") }
                }
                if let fw = device.firmware {
                    LabeledContent {
                        Text(fw).monospacedDigit().foregroundStyle(.secondary)
                    } label: { rowLabel("固件", "cpu") }
                }
                if let addr = device.address {
                    LabeledContent {
                        Text(addr)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } label: { rowLabel("蓝牙地址", "dot.radiowaves.left.and.right") }
                }
                if let name = device.name {
                    LabeledContent {
                        Text(name)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } label: { rowLabel("序列号", "number") }
                }
                if let vid = device.vendorID, let pid = device.productID {
                    LabeledContent {
                        Text("\(vid) / \(pid)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } label: { rowLabel("厂商 / 产品", "tag") }
                }
                if !device.interfaces.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(device.interfaces) { i in
                                HStack(spacing: 8) {
                                    Text(i.usageDescription)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 92, alignment: .leading)
                                    Text(i.label).font(.system(size: 11))
                                    Spacer()
                                    Text("输入 \(i.maxInput) · 功能 \(i.maxFeature)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        rowLabel("HID 接口（\(device.interfaces.count)）", "list.bullet.indent")
                    }
                }
            } else {
                Text("遥控器未连接")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("设备")
                Spacer()
                Button {
                    device.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .disabled(device.refreshing)
                .help("刷新设备信息")
            }
        } footer: {
            Text(device.updatedAt == nil
                 ? "macOS 不会直接暴露遥控器麦克风。"
                 : "电量和固件来自系统蓝牙信息。macOS 不会直接暴露遥控器麦克风。")
                .font(.system(size: 11))
        }
    }

    // MARK: - Sections

    private var cursorSection: some View {
        Section {
            slider(icon: "cursorarrow.motionlines", title: "速度",
                   value: $model.tune.cursorSpeed, range: 0.1...3.0,
                   minIcon: "tortoise.fill", maxIcon: "hare.fill",
                   display: { String(format: "%.2f×", $0) })
            slider(icon: "hand.raised.fill", title: "稳定度",
                   value: $model.tune.cursorDeadzone, range: 0.0...0.02,
                   minIcon: "scribble.variable", maxIcon: "hand.raised.fill",
                   display: { String(format: "%.0f", $0 * 1000) })
            Toggle(isOn: $model.tune.findCursorEnabled) {
                rowLabel("摇动时高亮指针", "cursorarrow.rays")
            }
            Toggle(isOn: $model.tune.focusFollowsCursor) {
                rowLabel("焦点跟随指针", "macwindow.on.rectangle")
            }
        } header: {
            Text("指针")
        } footer: {
            Text("稳定度越高，越会忽略手指抖动，按下点击时更不容易漂移。快速来回移动指针时，可以用高亮圈帮你找到鼠标位置。\n\n焦点跟随指针会让快捷键发送到指针所在的应用。它只会作用于已经占满当前显示器的窗口，避免打乱重叠窗口的层级。")
        }
    }

    private var accelerationSection: some View {
        Section {
            slider(icon: "tortoise.fill", title: "慢速倍率",
                   value: $model.tune.accelMin, range: 0.2...1.0,
                   minIcon: "tortoise.fill", maxIcon: "cursorarrow.motionlines",
                   display: { String(format: "%.2f×", $0) })
            slider(icon: "hare.fill", title: "快速倍率",
                   value: $model.tune.accelMax, range: 1.0...4.0,
                   minIcon: "cursorarrow.motionlines", maxIcon: "hare.fill",
                   display: { String(format: "%.2f×", $0) })
            slider(icon: "arrow.down.forward", title: "慢速阈值",
                   value: $model.tune.accelLowSpeed, range: 0.002...0.03,
                   minIcon: "tortoise.fill", maxIcon: "hare.fill",
                   display: { String(format: "%.0f", $0 * 1000) })
            slider(icon: "arrow.up.forward", title: "快速阈值",
                   value: $model.tune.accelHighSpeed, range: 0.02...0.12,
                   minIcon: "tortoise.fill", maxIcon: "hare.fill",
                   display: { String(format: "%.0f", $0 * 1000) })
        } header: {
            Text("指针加速度")
        } footer: {
            Text("手指慢速移动时指针更精细，快速滑动时指针移动更远。两个阈值决定慢速和快速倍率从哪里开始生效，中间会平滑过渡。")
        }
    }

    private var clickSection: some View {
        Section {
            slider(icon: "hand.tap.fill", title: "按压灵敏度",
                   value: $model.tune.clickRiseThreshold, range: 0.04...0.25,
                   minIcon: "hare.fill", maxIcon: "tortoise.fill",
                   display: { String(format: "%.2f", $0) })
            slider(icon: "arrow.up.and.down.and.arrow.left.and.right", title: "移动容忍度",
                   value: $model.tune.pressMoveMax, range: 0.01...0.06,
                   minIcon: "smallcircle.filled.circle.fill", maxIcon: "circle",
                   display: { String(format: "%.3f", $0) })
        } header: {
            Text("点击")
        } footer: {
            Text("按下点击时会短暂冻结指针，避免点击瞬间漂移。灵敏度越低越容易冻结；移动容忍度越高，手感越不容易发粘。")
        }
    }

    private var buttonsSection: some View {
        Section {
            slider(icon: "clock", title: "长按时间",
                   value: $model.tune.holdThreshold, range: 0.2...1.2,
                   minIcon: "hare.fill", maxIcon: "tortoise.fill",
                   display: { String(format: "%.1fs", $0) })
            slider(icon: "hand.tap.fill", title: "双击速度",
                   value: $model.tune.doubleTapWindow, range: 0.15...0.6,
                   minIcon: "hare.fill", maxIcon: "tortoise.fill",
                   display: { String(format: "%.2fs", $0) })
            slider(icon: "arrow.2.squarepath", title: "应用切换间隔",
                   value: $model.tune.appSwitcherStepInterval, range: 0.15...0.8,
                   minIcon: "hare.fill", maxIcon: "tortoise.fill",
                   display: { String(format: "%.2fs", $0) })
            slider(icon: "rectangle.on.rectangle", title: "桌面切换超时",
                   value: $model.tune.spacesModeWindow, range: 2.0...15.0,
                   minIcon: "hare.fill", maxIcon: "tortoise.fill",
                   display: { String(format: "%.0fs", $0) })
        } header: {
            Text("按键")
        } footer: {
            Text("长按时间决定按住多久触发 .hold 动作。双击速度决定第二次点击需要多快才算 .double。应用切换间隔控制 Cmd-Tab 选择应用时每跳一次的最短等待。桌面切换超时用于控制进入桌面切换状态后多久自动退出。")
        }
    }

    private var circularSection: some View {
        Section {
            Toggle(isOn: $model.tune.circularEnabled) {
                rowLabel("圆环滚动", "arrow.clockwise")
            }
            if model.tune.circularEnabled {
                slider(icon: "circle.dashed", title: "仅外圈",
                       value: $model.tune.circularMinRadius, range: 0.15...0.45,
                       minIcon: "smallcircle.filled.circle.fill", maxIcon: "circle",
                       display: { String(format: "%.0f%%", $0 * 100) })
                slider(icon: "timer", title: "启动阻力",
                       value: $model.tune.circularStartThreshold, range: 0.1...1.5,
                       minIcon: "hare.fill", maxIcon: "tortoise.fill",
                       display: { String(format: "%.0f°", $0 * 180 / .pi) })
                slider(icon: "speedometer", title: "滚动速度",
                       value: $model.tune.circularPixelsPerRadian, range: 40...400,
                       minIcon: "tortoise.fill", maxIcon: "hare.fill",
                       display: { String(format: "%.0f", $0) })
                slider(icon: "wind", title: "平滑度",
                       value: $model.tune.circularScrollEase, range: 0.1...0.6,
                       minIcon: "tortoise.fill", maxIcon: "hare.fill",
                       display: { String(format: "%.2f", $0) })

                // Velocity gain — shown as a curve, because four numbers do not tell you what the
                // wheel will feel like, and the shape does.
                VStack(alignment: .leading, spacing: 10) {
                    rowLabel("速度响应", "chart.xyaxis.line")
                    AccelCurveView(accelMin: model.tune.circularAccelMin,
                                   accelMax: model.tune.circularAccelMax,
                                   lowSpeed: model.tune.circularAccelLowSpeed,
                                   highSpeed: model.tune.circularAccelHighSpeed,
                                   curve: model.tune.circularAccelCurve)
                }
                .padding(.vertical, 2)

                slider(icon: "tortoise.fill", title: "慢速增益",
                       value: $model.tune.circularAccelMin, range: 0.1...1.5,
                       minIcon: "minus", maxIcon: "plus",
                       display: { String(format: "%.2f×", $0) })
                slider(icon: "hare.fill", title: "快速增益",
                       value: $model.tune.circularAccelMax, range: 1.0...5.0,
                       minIcon: "minus", maxIcon: "plus",
                       display: { String(format: "%.2f×", $0) })
                slider(icon: "point.topleft.down.curvedto.point.bottomright.up", title: "曲线形状",
                       value: $model.tune.circularAccelCurve, range: 0.4...4.0,
                       minIcon: "arrow.up.right", maxIcon: "arrow.turn.up.right",
                       display: { String(format: "%.1f", $0) })

                Toggle(isOn: $model.tune.circularInvert) {
                    rowLabel("反转方向", "arrow.left.arrow.right")
                }
            }
        } header: {
            Text("圆环滚动")
        } footer: {
            Text("手指沿触控板外圈画圆即可滚动，类似经典转盘。")
        }
        .animation(.easeInOut(duration: 0.22), value: model.tune.circularEnabled)
    }

    private var startupSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { launchAtLogin },
                set: { wanted in
                    do {
                        try LaunchAtLogin.setEnabled(wanted)
                        launchAtLoginError = nil
                    } catch {
                        launchAtLoginError = error.localizedDescription
                    }
                    // Always re-read the real registration rather than trusting `wanted`, so the
                    // switch cannot sit in a position macOS did not actually accept.
                    launchAtLogin = LaunchAtLogin.state.isOn
                }
            )) {
                rowLabel("登录时启动", "arrow.up.forward.app")
            }
            .disabled(LaunchAtLogin.state == .unavailable)
        } header: {
            Text("启动")
        } footer: {
            Text(launchAtLoginError.map { "无法更改：\($0)" }
                 ?? LaunchAtLogin.note
                 ?? "登录后自动运行 HyperVibe。也可以在系统设置 → 通用 → 登录项中管理。")
                .font(.system(size: 11))
                .foregroundStyle(launchAtLoginError == nil ? Color.secondary : Color.red)
        }
    }

    private var footerSection: some View {
        Section {
            Button(role: .destructive) {
                withAnimation { model.resetToDefaults() }
            } label: {
                rowLabel("恢复默认设置", "arrow.counterclockwise")
            }
        } footer: {
            Text("按键、圆环和滑动映射保存在 ~/.config/siriremote/config.jsonc")
                .font(.system(size: 11))
        }
    }

    // MARK: - Reusable rows

    private func rowLabel(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 18)
            Text(title).font(.system(size: 13))
        }
    }

    private func slider(icon: String, title: String, value: Binding<Double>,
                        range: ClosedRange<Double>, minIcon: String, maxIcon: String,
                        display: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                rowLabel(title, icon)
                Spacer()
                Text(display(value.wrappedValue))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 9) {
                Image(systemName: minIcon).font(.system(size: 11)).foregroundStyle(.tertiary)
                Slider(value: value, in: range)
                Image(systemName: maxIcon).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}
