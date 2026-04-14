import AppKit
import SwiftUI

private let optionAccentColor = Color(red: 139 / 255, green: 92 / 255, blue: 246 / 255)
private let commandAccentColor = Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255)
private let controlAccentColor = Color(red: 20 / 255, green: 184 / 255, blue: 166 / 255)
private let shiftAccentColor = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)

private enum AppPalette {
    static func windowBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(calibratedWhite: 0.11, alpha: 1))
            : Color(nsColor: .windowBackgroundColor)
    }

    static func surface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(calibratedWhite: 0.15, alpha: 1))
            : Color.white
    }

    static func secondarySurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(calibratedWhite: 0.18, alpha: 1))
            : Color.white
    }

    static func hoverSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(calibratedWhite: 0.22, alpha: 1))
            : Color.white
    }

    static func stroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.10)
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: AppLauncherViewModel
    @Environment(\.colorScheme) private var colorScheme
    let suppressInitialWindow: Bool
    @AppStorage("settings.useNumberKeys") private var useNumberKeys = false
    @AppStorage("settings.useFunctionKeys") private var useFunctionKeys = false
    @State private var assignRequest: ShortcutAssignRequest?
    @State private var managingShortcutID: String?
    @State private var hoveredShortcutID: String?
    private static let appIconCache = NSCache<NSString, NSImage>()

    private let keyScale: CGFloat = 1.35
    private var keyUnitWidth: CGFloat { 42 * keyScale }
    private var keyUnitHeight: CGFloat { keyUnitWidth }
    private var keySpacing: CGFloat { 6 * keyScale }

    private let keyboardRows: [[KeyboardKeySpec]] = [
        [
            .init(token: "f1", label: "F1"), .init(token: "f2", label: "F2"), .init(token: "f3", label: "F3"),
            .init(token: "f4", label: "F4"), .init(token: "f5", label: "F5"), .init(token: "f6", label: "F6"),
            .init(token: "f7", label: "F7"), .init(token: "f8", label: "F8"), .init(token: "f9", label: "F9"),
            .init(token: "f10", label: "F10"), .init(token: "f11", label: "F11"), .init(token: "f12", label: "F12")
        ],
        [
            .init(token: "1", label: "1"), .init(token: "2", label: "2"), .init(token: "3", label: "3"),
            .init(token: "4", label: "4"), .init(token: "5", label: "5"), .init(token: "6", label: "6"),
            .init(token: "7", label: "7"), .init(token: "8", label: "8"), .init(token: "9", label: "9"),
            .init(token: "0", label: "0"), .init(token: "-", label: "-"), .init(token: "=", label: "=")
        ],
        [
            .init(token: "q", label: "Q"), .init(token: "w", label: "W"), .init(token: "e", label: "E"),
            .init(token: "r", label: "R"), .init(token: "t", label: "T"), .init(token: "y", label: "Y"),
            .init(token: "u", label: "U"), .init(token: "i", label: "I"), .init(token: "o", label: "O"),
            .init(token: "p", label: "P"), .init(token: "[", label: "["), .init(token: "]", label: "]")
        ],
        [
            .init(token: "a", label: "A"), .init(token: "s", label: "S"), .init(token: "d", label: "D"),
            .init(token: "f", label: "F"), .init(token: "g", label: "G"), .init(token: "h", label: "H"),
            .init(token: "j", label: "J"), .init(token: "k", label: "K"), .init(token: "l", label: "L"), .init(token: ";", label: ";"), .init(token: "'", label: "'"),
        ],
        [
            .init(token: "z", label: "Z"), .init(token: "x", label: "X"), .init(token: "c", label: "C"),
            .init(token: "v", label: "V"), .init(token: "b", label: "B"), .init(token: "n", label: "N"), .init(token: "m", label: "M"),
            .init(token: ".", label: "."), .init(token: "/", label: "/")
        ]
    ]

    private var keyBackgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(nsColor: NSColor(calibratedWhite: 0.26, alpha: 1)),
                Color(nsColor: NSColor(calibratedWhite: 0.19, alpha: 1))
            ]
        }
        return [Color.white, Color(white: 0.95)]
    }

    private var keyLabelBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.48)
    }

    private var keyOuterShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.24) : Color.black.opacity(0.16)
    }

    private var innerKeyShadowColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.7)
    }

    private var legendInnerShadowColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.65)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(AppPalette.windowBackground(for: colorScheme))
                .ignoresSafeArea()

            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(AppPalette.surface(for: colorScheme))
                    .overlay(alignment: .topTrailing) {
                        Text(AppVersion.displayString)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color.secondary.opacity(colorScheme == .dark ? 0.42 : 0.58))
                            .padding(.top, 12)
                            .padding(.trailing, 14)
                    }
                    .overlay {
                        VStack(spacing: 11) {
                            if useFunctionKeys {
                                keyRow(keyboardRows[0])
                                    .transition(keyboardRowTransition)
                            }
                            if useNumberKeys {
                                keyRow(keyboardRows[1])
                                    .transition(keyboardRowTransition)
                            }
                            ForEach(Array(keyboardRows.dropFirst(2).enumerated()), id: \.offset) { _, row in
                                keyRow(row)
                            }
                        }
                        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: useFunctionKeys)
                        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: useNumberKeys)
                        .padding(14)
                    }
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(legendItems) { item in
                            modifierLegendKey(item: item)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            keyUsageToggle(
                                title: L10n.tr("settings.use_function_keys"),
                                systemImage: "keyboard.badge.eye",
                                isOn: $useFunctionKeys
                            )
                            keyUsageToggle(
                                title: L10n.tr("settings.use_number_keys"),
                                systemImage: "keyboard.badge.eye",
                                isOn: $useNumberKeys
                            )
                        }
                        .frame(maxWidth: 180, alignment: .trailing)
                    }
                    if !viewModel.topShortcutUsages.isEmpty {
                        Divider()
                        topShortcutUsageList
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppPalette.secondarySurface(for: colorScheme))
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)

            Text(L10n.tr("app.name"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 6)
                .ignoresSafeArea()

        }
        .sheet(item: $assignRequest) { request in
            ShortcutAssignSheet(viewModel: viewModel, key: request.key, existingShortcut: request.existingShortcut)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowStyleConfigurator(suppressOnLaunch: suppressInitialWindow))
        .onAppear {
            viewModel.setKeyUsage(useNumberKeys: useNumberKeys, useFunctionKeys: useFunctionKeys)
        }
        .onChange(of: useNumberKeys) { newValue in
            viewModel.setKeyUsage(useNumberKeys: newValue, useFunctionKeys: useFunctionKeys)
        }
        .onChange(of: useFunctionKeys) { newValue in
            viewModel.setKeyUsage(useNumberKeys: useNumberKeys, useFunctionKeys: newValue)
        }
    }

    private var enabledShortcuts: [AppShortcut] {
        viewModel.shortcuts.filter(\.enabled)
    }

    private func toggleManagementPopover(for shortcut: AppShortcut) {
        if managingShortcutID == shortcut.id {
            managingShortcutID = nil
        } else {
            managingShortcutID = shortcut.id
        }
    }

    private func presentAssignmentSheet(for key: KeyboardKeySpec) {
        assignRequest = ShortcutAssignRequest(key: key, existingShortcut: nil)
    }

    private func shortcuts(for keyToken: String) -> [AppShortcut] {
        let keyCode = ShortcutKeyMap.keyCode(for: keyToken)
        return enabledShortcuts
            .filter { shortcut in
                if let keyCode, let shortcutCode = ShortcutKeyMap.keyCode(for: shortcut.key) {
                    return keyCode == shortcutCode
                }
                return normalizeKey(shortcut.key) == normalizeKey(keyToken)
            }
            .sorted { $0.displayHotKey < $1.displayHotKey }
    }

    private func keyRow(_ row: [KeyboardKeySpec]) -> some View {
        HStack(spacing: keySpacing) {
            ForEach(row) { key in
                keyCap(key: key)
            }
        }
    }

    private var keyboardRowTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .scale(scale: 0.97, anchor: .top).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private func keyCap(key: KeyboardKeySpec) -> some View {
        let assignedShortcuts = shortcuts(for: key.token)
        let primaryShortcut = assignedShortcuts.first
        let hasAssignment = primaryShortcut != nil
        let colorStyle = primaryShortcut.map { keyColorStyle(for: $0) } ?? .none
        let keyWidth = key.widthUnits * keyUnitWidth
        let icon = primaryShortcut.flatMap { appIcon(for: $0.bundleIdentifier) }
        let isUnavailable = primaryShortcut.map { viewModel.unavailableShortcutIDs.contains($0.id) } ?? false

        let capVisual = ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: keyBackgroundGradientColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: keyWidth, height: keyUnitHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if let primaryShortcut {
                VStack {
                    Text(primaryShortcut.localizedName)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Spacer(minLength: 0)
            }

            if hasAssignment {
                keyTintFill(style: colorStyle)
            }

            if hasAssignment {
                Text(key.label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(keyLabelBackgroundColor)
                    )
                    .padding(5)
            } else {
                Text(key.label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }

            if isUnavailable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(4)
                    .background(
                        Circle()
                            .fill(AppPalette.hoverSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.9 : 0.78))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(4)
            }
        }
        .frame(width: keyWidth, height: keyUnitHeight)
        .shadow(
            color: keyOuterShadowColor,
            radius: colorScheme == .dark ? 5 : 6,
            x: 0,
            y: colorScheme == .dark ? 3 : 4
        )
        .shadow(
            color: innerKeyShadowColor,
            radius: 1.5,
            x: 0,
            y: -1
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppPalette.stroke(for: colorScheme).opacity(colorScheme == .dark ? 0.5 : 0.35), lineWidth: 1)
        )
        .overlay(
            keyTintStroke(hasAssignment: hasAssignment, style: colorStyle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isUnavailable ? Color.orange.opacity(0.72) : Color.clear, lineWidth: 1.2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))

        if let primaryShortcut {
            capVisual
                .overlay(alignment: .top) {
                    if hoveredShortcutID == primaryShortcut.id {
                        Text(primaryShortcut.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(AppPalette.hoverSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.96 : 0.92))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(AppPalette.stroke(for: colorScheme).opacity(colorScheme == .dark ? 0.7 : 0.45), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
                            .offset(y: -20)
                            .allowsHitTesting(false)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                    }
                }
                .overlay {
                    MacPointerCaptureView(
                        onLeftClick: { toggleManagementPopover(for: primaryShortcut) },
                        onRightClick: { toggleManagementPopover(for: primaryShortcut) },
                        onHoverChange: { isHovering in
                            withAnimation(.easeOut(duration: 0.12)) {
                                hoveredShortcutID = isHovering ? primaryShortcut.id : nil
                            }
                        }
                    )
                }
                .popover(
                    isPresented: Binding(
                        get: { managingShortcutID == primaryShortcut.id },
                        set: { isPresented in
                            if !isPresented, managingShortcutID == primaryShortcut.id {
                                managingShortcutID = nil
                            }
                        }
                    ),
                    arrowEdge: .bottom
                ) {
                    shortcutActionPopover(for: primaryShortcut, isUnavailable: isUnavailable)
                }
        } else {
            capVisual
                .overlay {
                    MacPointerCaptureView(
                        onLeftClick: { presentAssignmentSheet(for: key) },
                        onRightClick: { presentAssignmentSheet(for: key) }
                    )
                }
        }
    }

    private func appIcon(for bundleIdentifier: String) -> NSImage? {
        let cacheKey = bundleIdentifier as NSString
        if let cached = Self.appIconCache.object(forKey: cacheKey) {
            return cached
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let icon = NSWorkspace.shared.icon(forFile: appURL.path).copy() as? NSImage else {
            return nil
        }
        icon.size = NSSize(width: 18, height: 18)
        Self.appIconCache.setObject(icon, forKey: cacheKey)
        return icon
    }

    private func shortcutActionPopover(for shortcut: AppShortcut, isUnavailable: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(shortcut.localizedName)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .allowsHitTesting(false)

            Divider()

            if isUnavailable {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.orange)
                    Text(L10n.tr("manage.unavailable"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)

                Divider()
            }

            Button {
                assignRequest = ShortcutAssignRequest(
                    key: keySpec(forToken: shortcut.key),
                    existingShortcut: shortcut
                )
                managingShortcutID = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.tr("manage.change"))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
                .background(Color.black.opacity(0.001))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            Button(role: .destructive) {
                viewModel.deleteShortcut(id: shortcut.id)
                managingShortcutID = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(L10n.tr("manage.delete"))
                        .foregroundStyle(.red)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
                .background(Color.black.opacity(0.001))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 168)
        .padding(6)
    }

    private func normalizeKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func keyUsageToggle(title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .labelStyle(.titleAndIcon)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Color(hue: 0.58, saturation: 0.45, brightness: 0.85))
                .scaleEffect(0.86)
        }
        .help(title)
    }

    @State private var confirmClearUsage = false

    private var topShortcutUsageList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.topShortcutUsages.isEmpty {
                HStack(spacing: 4) {
                    Label(L10n.tr("usage.top_shortcuts_title"), systemImage: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .semibold))
                    Button {
                        if confirmClearUsage {
                            viewModel.clearShortcutUsageHistory()
                            confirmClearUsage = false
                        } else {
                            confirmClearUsage = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                confirmClearUsage = false
                            }
                        }
                    } label: {
                        Image(systemName: confirmClearUsage ? "checkmark.circle.fill" : "eraser.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(confirmClearUsage ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("usage.clear_history"))
                    Spacer(minLength: 0)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 170), spacing: 6, alignment: .leading)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(viewModel.topShortcutUsages, id: \.id) { usage in
                        topShortcutUsageRow(usage: usage)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func topShortcutUsageRow(usage: ShortcutUsageStat) -> some View {
        HStack(spacing: 5) {
            if let icon = appIcon(for: usage.shortcut.bundleIdentifier) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text(usage.shortcut.localizedName)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(launchCountDisplayText(usage.launchCount))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.18 : 0.08))
        )
    }

    private func launchCountDisplayText(_ launchCount: Int) -> String {
        if launchCount > 999 {
            return L10n.tr("usage.launch_count_overflow")
        }
        return L10n.format("usage.launch_count", launchCount)
    }

    private func keySpec(forToken token: String) -> KeyboardKeySpec {
        let allKeys = keyboardRows.flatMap { $0 }
        if let tokenCode = ShortcutKeyMap.keyCode(for: token),
           let existing = allKeys.first(where: { ShortcutKeyMap.keyCode(for: $0.token) == tokenCode }) {
            return existing
        }
        let normalizedToken = normalizeKey(token)
        if let existing = allKeys.first(where: { normalizeKey($0.token) == normalizedToken }) {
            return existing
        }
        return KeyboardKeySpec(token: token, label: ShortcutKeyMap.displayName(for: token))
    }

    private var legendItems: [LegendItem] {
        [
            LegendItem(id: "option", symbol: "⌥", title: L10n.tr("legend.option"), style: .option),
            LegendItem(id: "command", symbol: "⌘", title: L10n.tr("legend.command"), style: .command),
            LegendItem(id: "control", symbol: "⌃", title: L10n.tr("legend.control"), style: .control),
            LegendItem(id: "shift", symbol: "⇧", title: L10n.tr("legend.shift"), style: .shift)
        ]
    }

    private func modifierLegendKey(item: LegendItem) -> some View {
        return ZStack {
            legendFill(style: item.style)

            VStack(spacing: 3) {
                Text(item.symbol)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .frame(height: 12)
                Text(item.title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .frame(height: 10)
            }
            .frame(height: 25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .foregroundStyle(.primary)
        }
        .frame(width: keyUnitWidth, height: keyUnitHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppPalette.surface(for: colorScheme))
        )
        .shadow(
            color: Color.black.opacity(0.14),
            radius: 5,
            x: 0,
            y: 3
        )
        .shadow(
            color: legendInnerShadowColor,
            radius: 1.2,
            x: 0,
            y: -1
        )
        .overlay(
            legendStroke(style: item.style)
        )
    }

    private func keyColorStyle(for shortcut: AppShortcut) -> TriggerColorStyle {
        if shortcut.modifiers.contains(.option) {
            return .option
        }
        if shortcut.modifiers.contains(.command) {
            return .command
        }
        if shortcut.modifiers.contains(.control) {
            return .control
        }
        if shortcut.modifiers.contains(.shift) {
            return .shift
        }
        return .none
    }

    @ViewBuilder
    private func keyTintFill(style: TriggerColorStyle) -> some View {
        switch style {
        case .none:
            EmptyView()
        case .option:
            RoundedRectangle(cornerRadius: 10)
                .fill(optionAccentColor.opacity(0.22))
        case .command:
            RoundedRectangle(cornerRadius: 10)
                .fill(commandAccentColor.opacity(0.22))
        case .control:
            RoundedRectangle(cornerRadius: 10)
                .fill(controlAccentColor.opacity(0.22))
        case .shift:
            RoundedRectangle(cornerRadius: 10)
                .fill(shiftAccentColor.opacity(0.24))
        }
    }

    @ViewBuilder
    private func keyTintStroke(hasAssignment: Bool, style: TriggerColorStyle) -> some View {
        if !hasAssignment || style == .none {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.14), lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .stroke(strokeColor(for: style), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func legendFill(style: TriggerColorStyle) -> some View {
        switch style {
        case .option:
            RoundedRectangle(cornerRadius: 8).fill(optionAccentColor.opacity(0.24))
        case .command:
            RoundedRectangle(cornerRadius: 8).fill(commandAccentColor.opacity(0.24))
        case .control:
            RoundedRectangle(cornerRadius: 8).fill(controlAccentColor.opacity(0.24))
        case .shift:
            RoundedRectangle(cornerRadius: 8).fill(shiftAccentColor.opacity(0.24))
        case .none:
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.18))
        }
    }

    @ViewBuilder
    private func legendStroke(style: TriggerColorStyle) -> some View {
        switch style {
        case .option:
            RoundedRectangle(cornerRadius: 8).stroke(optionAccentColor.opacity(0.55), lineWidth: 1)
        case .command:
            RoundedRectangle(cornerRadius: 8).stroke(commandAccentColor.opacity(0.55), lineWidth: 1)
        case .control:
            RoundedRectangle(cornerRadius: 8).stroke(controlAccentColor.opacity(0.62), lineWidth: 1)
        case .shift:
            RoundedRectangle(cornerRadius: 8).stroke(shiftAccentColor.opacity(0.68), lineWidth: 1)
        case .none:
            RoundedRectangle(cornerRadius: 8).stroke(AppPalette.stroke(for: colorScheme).opacity(colorScheme == .dark ? 0.75 : 0.45), lineWidth: 1)
        }
    }

    private func strokeColor(for style: TriggerColorStyle) -> Color {
        switch style {
        case .option:
            return optionAccentColor.opacity(0.55)
        case .command:
            return commandAccentColor.opacity(0.55)
        case .control:
            return controlAccentColor.opacity(0.62)
        case .shift:
            return shiftAccentColor.opacity(0.68)
        case .none:
            return AppPalette.stroke(for: colorScheme).opacity(colorScheme == .dark ? 0.75 : 0.45)
        }
    }
}

private enum TriggerColorStyle {
    case none
    case option
    case command
    case control
    case shift
}

private struct LegendItem: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let style: TriggerColorStyle
}

private struct KeyboardKeySpec: Hashable, Identifiable {
    let token: String
    let label: String
    let widthUnits: CGFloat

    init(token: String, label: String, widthUnits: CGFloat = 1) {
        self.token = token
        self.label = label
        self.widthUnits = widthUnits
    }

    var id: String { token }
}

private struct ShortcutAssignRequest: Identifiable {
    let id = UUID()
    let key: KeyboardKeySpec
    let existingShortcut: AppShortcut?
}

private enum TriggerPreset: String, CaseIterable, Identifiable {
    case option
    case command
    case control
    case shift

    var id: String { rawValue }

    var modifiers: [ShortcutModifier] {
        switch self {
        case .option:
            return [.option]
        case .command:
            return [.command]
        case .control:
            return [.control]
        case .shift:
            return [.shift]
        }
    }

    var title: String {
        switch self {
        case .option:
            return L10n.tr("assign.trigger.option")
        case .command:
            return L10n.tr("assign.trigger.command")
        case .control:
            return L10n.tr("assign.trigger.control")
        case .shift:
            return L10n.tr("assign.trigger.shift")
        }
    }
}

private struct ShortcutAssignSheet: View {
    @ObservedObject var viewModel: AppLauncherViewModel
    @Environment(\.colorScheme) private var colorScheme
    let key: KeyboardKeySpec
    let existingShortcut: AppShortcut?
    private static let appIconCache = NSCache<NSString, NSImage>()

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedAppID: String?
    @State private var apps: [InstalledApplication] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var triggerPreset: TriggerPreset = .option

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existingShortcut == nil ? L10n.format("assign.title", key.label) : L10n.format("assign.edit_title", key.label))
                .font(.headline)

            triggerPresetPanel

            if !isSaving, let conflictingShortcut {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(L10n.format("assign.conflict", conflictingShortcut.displayHotKey, conflictingShortcut.name))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.10))
                )
            }

            if !isSaving, let systemConflictMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(systemConflictMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.yellow)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.yellow.opacity(colorScheme == .dark ? 0.18 : 0.12))
                )
            }

            TextField(L10n.tr("assign.search.placeholder"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            Group {
                if isLoading {
                    ProgressView(L10n.tr("assign.loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if recommendedApps.isEmpty, searchableApps.isEmpty {
                    Text(L10n.tr("assign.no_results"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List(selection: $selectedAppID) {
                        if !recommendedApps.isEmpty {
                            ForEach(recommendedApps) { app in
                                appListRow(for: app, isRecommended: true)
                                    .tag(app.id)
                            }
                        }

                        ForEach(searchableApps) { app in
                            appListRow(for: app)
                                .tag(app.id)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                Button(L10n.tr("assign.cancel")) {
                    dismiss()
                }
                Button(existingShortcut == nil ? L10n.tr("assign.add") : L10n.tr("assign.save")) {
                    addShortcut()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedApp == nil || conflictingShortcut != nil || isSaving)
            }
        }
        .padding(16)
        .frame(width: 560, height: 600)
        .background(AppPalette.windowBackground(for: colorScheme))
        .task {
            await loadApps()
        }
    }

    private var filteredApps: [InstalledApplication] {
        guard searchKeyword.isEmpty else {
            return apps.filter {
                $0.name.localizedCaseInsensitiveContains(searchKeyword) ||
                $0.bundleIdentifier.localizedCaseInsensitiveContains(searchKeyword)
            }
        }
        return apps
    }

    private var searchKeyword: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowRecommendations: Bool {
        searchKeyword.isEmpty
    }

    private var searchableApps: [InstalledApplication] {
        guard shouldShowRecommendations else {
            return filteredApps
        }
        let recommendedIDs = Set(recommendedApps.map(\.id))
        return filteredApps.filter { !recommendedIDs.contains($0.id) }
    }

    private var recommendationKey: String? {
        guard shouldShowRecommendations else {
            return nil
        }
        let token = key.token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard token.count == 1,
              let scalar = token.unicodeScalars.first,
              CharacterSet.letters.contains(scalar) else {
            return nil
        }
        return token
    }

    private var recommendedApps: [InstalledApplication] {
        guard let recommendationKey else { return [] }

        return apps
            .filter { isRecommendationCandidate($0) }
            .compactMap { app -> (score: Int, app: InstalledApplication)? in
                recommendationScore(for: app.name, key: recommendationKey).map { ($0, app) }
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
                }
                return lhs.score < rhs.score
            }
            .map(\.app)
            .prefix(4)
            .map { $0 }
    }

    private func isRecommendationCandidate(_ app: InstalledApplication) -> Bool {
        let normalizedName = app.name
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let normalizedBundle = app.bundleIdentifier.lowercased()

        if normalizedBundle.hasPrefix("com.apple.") {
            return false
        }
        if normalizedName.contains("uikitsystem") {
            return false
        }
        if normalizedBundle.contains("uikitsystemapp") || normalizedBundle.contains("com.apple.uikit") {
            return false
        }
        return true
    }

    private var selectedApp: InstalledApplication? {
        guard let selectedAppID else { return nil }
        return apps.first(where: { $0.id == selectedAppID })
    }

    private var conflictingShortcut: AppShortcut? {
        viewModel.conflictingShortcut(
            forKey: key.token,
            modifiers: triggerPreset.modifiers,
            excludingShortcutID: existingShortcut?.id
        )
    }

    private var systemConflictMessage: String? {
        let ids = viewModel.systemShortcutConflictIDs(forKey: key.token, modifiers: triggerPreset.modifiers)
        guard !ids.isEmpty else { return nil }

        let idText = ids.map(String.init).joined(separator: ", ")
        return L10n.format("assign.system_conflict", idText)
    }

    private var triggerPresetPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("assign.trigger.label"))
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                triggerKeyCard(symbol: "⌥", title: L10n.tr("legend.option"), preset: .option)
                triggerKeyCard(symbol: "⌘", title: L10n.tr("legend.command"), preset: .command)
                triggerKeyCard(symbol: "⌃", title: L10n.tr("legend.control"), preset: .control)
                triggerKeyCard(symbol: "⇧", title: L10n.tr("legend.shift"), preset: .shift)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
    }

    private func triggerKeyCard(
        symbol: String,
        title: String,
        preset: TriggerPreset
    ) -> some View {
        let isActive = triggerPreset == preset
        let activeFill: AnyShapeStyle = {
            switch preset {
            case .option:
                return AnyShapeStyle(optionAccentColor.opacity(0.24))
            case .command:
                return AnyShapeStyle(commandAccentColor.opacity(0.24))
            case .control:
                return AnyShapeStyle(controlAccentColor.opacity(0.24))
            case .shift:
                return AnyShapeStyle(shiftAccentColor.opacity(0.24))
            }
        }()
        let activeStroke: AnyShapeStyle = {
            switch preset {
            case .option:
                return AnyShapeStyle(optionAccentColor.opacity(0.65))
            case .command:
                return AnyShapeStyle(commandAccentColor.opacity(0.65))
            case .control:
                return AnyShapeStyle(controlAccentColor.opacity(0.70))
            case .shift:
                return AnyShapeStyle(shiftAccentColor.opacity(0.72))
            }
        }()

        return Button {
            triggerPreset = preset
        } label: {
            VStack(spacing: 3) {
                Text(symbol)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .frame(width: 56, height: 56)
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? activeFill : AnyShapeStyle(Color.secondary.opacity(0.10)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? activeStroke : AnyShapeStyle(Color.secondary.opacity(0.25)), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func appListRow(for app: InstalledApplication, isRecommended: Bool = false) -> some View {
        let hasCurrentShortcut = appHasCurrentShortcut(app)
        let existingBindingsText = appExistingBindingsText(app)

        return HStack(spacing: 10) {
            appRowIcon(for: app)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if isRecommended {
                    Text(L10n.tr("assign.recommend.badge"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                }

                if hasCurrentShortcut {
                    Text(L10n.tr("assign.binding.current"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.14), in: Capsule())
                } else if let existingBindingsText {
                    Text(existingBindingsText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }
            }
        }
        .contentShape(Rectangle())
        .overlay {
            MacPointerCaptureView(
                onLeftClick: { selectedAppID = app.id },
                onDoubleLeftClick: {
                    selectedAppID = app.id
                    addShortcut(app)
                },
                onRightClick: {}
            )
        }
    }

    private func appShortcuts(for app: InstalledApplication) -> [AppShortcut] {
        viewModel.shortcuts
            .filter { $0.enabled && $0.bundleIdentifier == app.bundleIdentifier }
            .sorted { $0.displayHotKey < $1.displayHotKey }
    }

    private func appHasCurrentShortcut(_ app: InstalledApplication) -> Bool {
        appShortcuts(for: app).contains { shortcut in
            sameShortcut(shortcut, keyToken: key.token, modifiers: triggerPreset.modifiers)
        }
    }

    private func appExistingBindingsText(_ app: InstalledApplication) -> String? {
        let hotKeys = appShortcuts(for: app).map(\.displayHotKey)
        guard !hotKeys.isEmpty else { return nil }

        if hotKeys.count <= 2 {
            return L10n.format("assign.binding.single", hotKeys.joined(separator: " "))
        }

        let preview = hotKeys.prefix(2).joined(separator: " ")
        return L10n.format("assign.binding.multiple", preview, hotKeys.count - 2)
    }

    private func sameShortcut(_ shortcut: AppShortcut, keyToken: String, modifiers: [ShortcutModifier]) -> Bool {
        let normalizedShortcutKey = shortcut.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTargetKey = keyToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let sameKey: Bool = {
            if let shortcutKeyCode = ShortcutKeyMap.keyCode(for: normalizedShortcutKey),
               let targetKeyCode = ShortcutKeyMap.keyCode(for: normalizedTargetKey) {
                return shortcutKeyCode == targetKeyCode
            }
            return normalizedShortcutKey == normalizedTargetKey
        }()

        guard sameKey else { return false }
        return normalizedModifiers(shortcut.modifiers) == normalizedModifiers(modifiers)
    }

    private func normalizedModifiers(_ modifiers: [ShortcutModifier]) -> [ShortcutModifier] {
        let modifierSet = Set(modifiers)
        let order: [ShortcutModifier] = [.command, .option, .control, .shift]
        return order.filter { modifierSet.contains($0) }
    }

    private func loadApps() async {
        isLoading = true
        viewModel.refreshSystemShortcuts()
        let installedApps = await viewModel.fetchInstalledApps(forceRefresh: true)
        apps = installedApps
        if let existingShortcut {
            selectedAppID = installedApps.first(where: { $0.bundleIdentifier == existingShortcut.bundleIdentifier })?.id
            triggerPreset = preset(for: existingShortcut.modifiers)
        } else {
            selectedAppID = recommendedApps.first?.id ?? searchableApps.first?.id ?? installedApps.first?.id
        }
        isLoading = false
    }

    private func addShortcut() {
        guard let app = selectedApp else { return }
        addShortcut(app)
    }

    private func addShortcut(_ app: InstalledApplication) {
        guard !isSaving else { return }
        guard conflictingShortcut == nil else { return }
        isSaving = true
        let didSave = viewModel.addShortcut(
            forKey: key.token,
            app: app,
            modifiers: triggerPreset.modifiers,
            replacingShortcutID: existingShortcut?.id
        )
        if didSave {
            dismiss()
        } else {
            isSaving = false
        }
    }

    private func preset(for modifiers: [ShortcutModifier]) -> TriggerPreset {
        if modifiers.contains(.command) {
            return .command
        }
        if modifiers.contains(.control) {
            return .control
        }
        if modifiers.contains(.shift) {
            return .shift
        }
        return .option
    }

    @ViewBuilder
    private func appRowIcon(for app: InstalledApplication) -> some View {
        if let icon = appIcon(for: app.bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func appIcon(for bundleIdentifier: String) -> NSImage? {
        let cacheKey = bundleIdentifier as NSString
        if let cached = Self.appIconCache.object(forKey: cacheKey) {
            return cached
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let icon = NSWorkspace.shared.icon(forFile: appURL.path).copy() as? NSImage else {
            return nil
        }
        icon.size = NSSize(width: 24, height: 24)
        Self.appIconCache.setObject(icon, forKey: cacheKey)
        return icon
    }

    private func recommendationScore(for appName: String, key: String) -> Int? {
        let normalizedName = appName
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        if normalizedName.hasPrefix(key) {
            return 0
        }

        let words = normalizedName.split { character in
            !character.isLetter && !character.isNumber
        }
        if words.contains(where: { $0.hasPrefix(key) }) {
            return 1
        }

        return nil
    }
}


private struct MacPointerCaptureView: NSViewRepresentable {
    var onLeftClick: () -> Void
    var onDoubleLeftClick: (() -> Void)? = nil
    var onRightClick: () -> Void
    var onHoverChange: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> PointerCaptureNSView {
        let view = PointerCaptureNSView()
        updateView(view)
        return view
    }

    func updateNSView(_ nsView: PointerCaptureNSView, context: Context) {
        updateView(nsView)
    }

    private func updateView(_ view: PointerCaptureNSView) {
        view.onLeftClick = onLeftClick
        view.onDoubleLeftClick = onDoubleLeftClick
        view.onRightClick = onRightClick
        view.onHoverChange = onHoverChange
    }
}

private final class PointerCaptureNSView: NSView {
    var onLeftClick: () -> Void = {}
    var onDoubleLeftClick: (() -> Void)?
    var onRightClick: () -> Void = {}
    var onHoverChange: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let tracking = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(tracking)
        self.tracking = tracking
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleLeftClick?()
            return
        }
        onLeftClick()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick()
    }
}

private struct WindowStyleConfigurator: NSViewRepresentable {
    let suppressOnLaunch: Bool
    private static var didSuppressInitialWindow = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindowIfNeeded(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindowIfNeeded(from: nsView)
        }
    }

    private func configureWindowIfNeeded(from view: NSView) {
        guard let window = view.window else { return }
        window.isOpaque = true
        window.appearance = nil
        window.backgroundColor = .windowBackgroundColor
        window.toolbar = nil
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        if suppressOnLaunch, !Self.didSuppressInitialWindow {
            window.orderOut(nil)
            Self.didSuppressInitialWindow = true
        }
    }
}
