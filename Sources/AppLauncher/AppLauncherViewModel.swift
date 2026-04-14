import AppKit
import CoreGraphics
import Darwin
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppLauncherViewModel: ObservableObject {
    @Published var shortcuts: [AppShortcut] = []
    @Published private(set) var profiles: [ShortcutProfile] = []
    @Published private(set) var activeProfileID = ""
    @Published var launchErrorMessage: String?
    @Published var registrationWarnings: [String] = []
    @Published var unavailableShortcutIDs: Set<String> = []
    @Published var statusMessage: String?
    @Published var launchAtLoginEnabled = false
    @Published var showDockIcon = false
    @Published var topShortcutUsages: [ShortcutUsageStat] = []
    @Published private(set) var hotKeysPaused = false

    private let store: ShortcutStore
    private var shortcutFileMonitor: DispatchSourceFileSystemObject?
    private var monitoredFileDescriptor: CInt = -1
    private var lastForegroundBundleByTarget: [String: String] = [:]
    private var recentForegroundBundles: [String] = []
    private var activationObserver: NSObjectProtocol?
    private let appBundleIdentifier = Bundle.main.bundleIdentifier
    private var cachedInstalledApps: [InstalledApplication]?
    private var systemShortcuts: [SystemShortcutEntry] = []
    private var pendingLaunchDatesByBundleIdentifier: [String: Date] = [:]
    private var useNumberKeys = false
    private var useFunctionKeys = false
    private let keyUsageDefaults = UserDefaults.standard
    private let shortcutUsageByDayDefaultsKey = "stats.shortcutUsageByDay"
    private let shortcutUsageLegacyDefaultsKey = "stats.shortcutUsageCounts"
    private let hotKeysPausedDefaultsKey = "hotkeys.paused"
    private let showDockIconDefaultsKey = "settings.showDockIcon"
    private let usageWindowDays = 7
    private let topUsageDisplayLimit = 10
    private let topUsageMinimumLaunchCount = 3
    private let topUsageMinimumDisplayCount = 3
    private let pendingLaunchSuppressionInterval: TimeInterval = 4
    private var shortcutUsageByDay: [String: [String: Int]] = [:]
    private let numberRowKeyCodes: Set<UInt32> = Set(
        ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "=", "_", "+"]
            .compactMap { ShortcutKeyMap.keyCode(for: $0) }
    )

    init(store: ShortcutStore = ShortcutStore()) {
        self.store = store
        loadKeyUsageSettings()
        loadDockIconSetting()
        loadShortcutUsageCounts()
        loadHotKeyPauseState()
        refreshSystemShortcuts()
        bindHotKeyHandler()
        startTrackingForegroundApps()
        syncLaunchAtLoginStatus()
        reloadShortcuts(updateStatusMessage: true)
        startMonitoringShortcutFile()
    }

    var configFilePath: String {
        store.fileURL.path
    }

    var activeProfile: ShortcutProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    var activeProfileName: String {
        activeProfile?.name ?? L10n.tr("profiles.default_name")
    }

    var canDeleteActiveProfile: Bool {
        profiles.count > 1
    }

    func reloadShortcuts(updateStatusMessage: Bool = false) {
        do {
            applyDocument(try store.loadDocument())
            if updateStatusMessage {
                statusMessage = L10n.format("status.shortcuts_loaded", shortcuts.count)
            }
            launchErrorMessage = nil
        } catch {
            shortcuts = []
            profiles = []
            activeProfileID = ""
            registrationWarnings = []
            unavailableShortcutIDs = []
            topShortcutUsages = []
            statusMessage = nil
            launchErrorMessage = L10n.format("error.shortcuts_load_failed", error.localizedDescription)
        }
    }

    func openConfigFile() {
        NSWorkspace.shared.open(store.fileURL)
    }

    func fetchInstalledApps(forceRefresh: Bool = false) async -> [InstalledApplication] {
        if !forceRefresh, let cachedInstalledApps {
            return cachedInstalledApps
        }

        let apps = await Task.detached {
            ApplicationScanner().installedApps()
        }.value
        cachedInstalledApps = apps
        return apps
    }

    var isHotKeysPaused: Bool {
        hotKeysPaused
    }

    func pauseHotKeys() {
        guard !hotKeysPaused else { return }
        hotKeysPaused = true
        keyUsageDefaults.set(true, forKey: hotKeysPausedDefaultsKey)
        applyHotKeyRegistration()
        statusMessage = L10n.tr("status.hotkeys_paused")
    }

    func resumeHotKeys() {
        guard hotKeysPaused else { return }
        hotKeysPaused = false
        keyUsageDefaults.removeObject(forKey: hotKeysPausedDefaultsKey)
        applyHotKeyRegistration()
        statusMessage = L10n.tr("status.hotkeys_resumed")
    }

    func exportShortcuts() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "shortcuts.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(currentDocument.normalized())
            try data.write(to: url, options: [.atomic])
            statusMessage = L10n.format("status.shortcuts_exported", currentDocument.totalShortcutCount)
            launchErrorMessage = nil
        } catch {
            launchErrorMessage = L10n.format("error.shortcuts_export_failed", error.localizedDescription)
        }
    }

    func importShortcuts() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let importedDocument = try store.decodeDocument(from: data)
            try store.saveDocument(importedDocument)
            cachedInstalledApps = nil
            reloadShortcuts()
            statusMessage = L10n.format("status.shortcuts_imported", importedDocument.totalShortcutCount)
            launchErrorMessage = nil
        } catch {
            launchErrorMessage = L10n.format("error.shortcuts_import_failed", error.localizedDescription)
        }
    }

    func refreshSystemShortcuts() {
        systemShortcuts = loadSystemShortcuts()
    }

    func systemShortcutConflictIDs(forKey key: String, modifiers: [ShortcutModifier]) -> [Int] {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let keyCode = ShortcutKeyMap.keyCode(for: normalizedKey) else {
            return []
        }
        let normalizedModifiers = normalizedModifiersFrom(modifiers)
        return systemShortcuts
            .filter { entry in
                entry.keyCode == keyCode &&
                normalizedModifiersFrom(entry.modifiers) == normalizedModifiers
            }
            .map(\.id)
    }

    @discardableResult
    func addShortcut(forKey key: String, app: InstalledApplication, modifiers: [ShortcutModifier]) -> Bool {
        addShortcut(forKey: key, app: app, modifiers: modifiers, replacingShortcutID: nil)
    }

    @discardableResult
    func addShortcut(
        forKey key: String,
        app: InstalledApplication,
        modifiers: [ShortcutModifier],
        replacingShortcutID: String?
    ) -> Bool {
        if let conflictingShortcut = conflictingShortcut(
            forKey: key,
            modifiers: modifiers,
            excludingShortcutID: replacingShortcutID
        ) {
            launchErrorMessage = L10n.format(
                "error.shortcut_conflict",
                conflictingShortcut.displayHotKey,
                conflictingShortcut.name
            )
            return false
        }

        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedModifiers = normalizedModifiersFrom(modifiers)

        var updatedShortcuts = shortcuts
        if let replacingShortcutID {
            updatedShortcuts.removeAll { $0.id == replacingShortcutID }
        }

        updatedShortcuts.append(
            AppShortcut(
                id: "\(app.bundleIdentifier)-\(normalizedKey)-\(normalizedModifiers.map(\.rawValue).joined(separator: "-"))",
                name: app.name,
                bundleIdentifier: app.bundleIdentifier,
                key: normalizedKey,
                modifiers: normalizedModifiers,
                enabled: true
            )
        )

        return updateActiveProfileShortcuts(
            updatedShortcuts,
            successMessage: L10n.tr("status.shortcut_added"),
            errorKey: "error.shortcut_save_failed"
        )
    }

    func conflictingShortcut(
        forKey key: String,
        modifiers: [ShortcutModifier],
        excludingShortcutID: String? = nil
    ) -> AppShortcut? {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedModifiers = normalizedModifiersFrom(modifiers)
        let targetKeyCode = ShortcutKeyMap.keyCode(for: normalizedKey)

        return shortcuts.first { shortcut in
            if let excludingShortcutID, shortcut.id == excludingShortcutID {
                return false
            }

            guard normalizedModifiersFrom(shortcut.modifiers) == normalizedModifiers else {
                return false
            }

            let shortcutKey = shortcut.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let targetKeyCode, let shortcutKeyCode = ShortcutKeyMap.keyCode(for: shortcutKey) {
                return targetKeyCode == shortcutKeyCode
            }
            return shortcutKey == normalizedKey
        }
    }

    func deleteShortcut(id: String) {
        let updatedShortcuts = shortcuts.filter { $0.id != id }
        _ = updateActiveProfileShortcuts(
            updatedShortcuts,
            successMessage: L10n.tr("status.shortcut_deleted"),
            errorKey: "error.shortcut_delete_failed"
        )
    }

    func selectProfile(id: String) {
        guard id != activeProfileID else { return }
        let updatedDocument = ShortcutProfilesDocument(activeProfileID: id, profiles: profiles).normalized()

        do {
            try store.saveDocument(updatedDocument)
            applyDocument(updatedDocument)
            statusMessage = L10n.format("status.profile_switched", activeProfileName)
            launchErrorMessage = nil
        } catch {
            launchErrorMessage = L10n.format("error.profile_save_failed", error.localizedDescription)
        }
    }

    func createProfile() {
        let newProfile = ShortcutProfile(
            name: nextProfileName(),
            shortcuts: []
        )
        var updatedProfiles = profiles
        updatedProfiles.append(newProfile)
        persistProfiles(
            updatedProfiles,
            activeProfileID: newProfile.id,
            successMessage: L10n.format("status.profile_created", newProfile.name),
            errorKey: "error.profile_save_failed"
        )
    }

    func renameActiveProfile(to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let activeProfile else { return }
        guard !trimmedName.isEmpty else { return }
        guard activeProfile.name != trimmedName else { return }

        let updatedProfiles = profiles.map { profile in
            guard profile.id == activeProfile.id else { return profile }
            var updatedProfile = profile
            updatedProfile.name = trimmedName
            return updatedProfile
        }

        persistProfiles(
            updatedProfiles,
            activeProfileID: activeProfile.id,
            successMessage: L10n.format("status.profile_renamed", trimmedName),
            errorKey: "error.profile_save_failed"
        )
    }

    func deleteActiveProfile() {
        guard let activeProfile, canDeleteActiveProfile else { return }

        let remainingProfiles = profiles.filter { $0.id != activeProfile.id }
        let nextActiveProfileID = remainingProfiles.first?.id ?? ""
        let usageKeyPrefix = "\(activeProfile.id)|"
        let retainedUsageHistory = shortcutUsageByDay.filter { !$0.key.hasPrefix(usageKeyPrefix) }
        let didPersist = persistProfiles(
            remainingProfiles,
            activeProfileID: nextActiveProfileID,
            successMessage: L10n.format("status.profile_deleted", activeProfile.name),
            errorKey: "error.profile_delete_failed"
        )
        if didPersist {
            shortcutUsageByDay = retainedUsageHistory
            pruneAndPersistShortcutUsageByDay()
        }
    }

    private var currentDocument: ShortcutProfilesDocument {
        ShortcutProfilesDocument(activeProfileID: activeProfileID, profiles: profiles).normalized()
    }

    private func applyDocument(_ document: ShortcutProfilesDocument) {
        let normalizedDocument = document.normalized()
        profiles = normalizedDocument.profiles
        activeProfileID = normalizedDocument.activeProfileID
        migrateShortcutUsageHistoryIfNeeded(defaultProfileID: activeProfileID)
        shortcuts = normalizedDocument.activeProfile?.shortcuts ?? []
        applyHotKeyRegistration()
        refreshTopShortcutUsages()
    }

    @discardableResult
    private func updateActiveProfileShortcuts(
        _ updatedShortcuts: [AppShortcut],
        successMessage: String,
        errorKey: String
    ) -> Bool {
        guard let activeProfile else {
            launchErrorMessage = L10n.tr("error.profile_missing")
            return false
        }

        let updatedProfiles = profiles.map { profile in
            guard profile.id == activeProfile.id else { return profile }
            var updatedProfile = profile
            updatedProfile.shortcuts = updatedShortcuts
            return updatedProfile
        }

        return persistProfiles(
            updatedProfiles,
            activeProfileID: activeProfile.id,
            successMessage: successMessage,
            errorKey: errorKey
        )
    }

    @discardableResult
    private func persistProfiles(
        _ updatedProfiles: [ShortcutProfile],
        activeProfileID: String,
        successMessage: String?,
        errorKey: String
    ) -> Bool {
        let updatedDocument = ShortcutProfilesDocument(
            activeProfileID: activeProfileID,
            profiles: updatedProfiles
        ).normalized()

        do {
            try store.saveDocument(updatedDocument)
            applyDocument(updatedDocument)
            if let successMessage {
                statusMessage = successMessage
            }
            launchErrorMessage = nil
            return true
        } catch {
            launchErrorMessage = L10n.format(errorKey, error.localizedDescription)
            return false
        }
    }

    private func nextProfileName() -> String {
        let existingNames = Set(
            profiles.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )

        var index = 1
        while true {
            let candidate = index == 1
                ? L10n.tr("profiles.default_name")
                : L10n.format("profiles.auto_name", index)
            if !existingNames.contains(candidate.lowercased()) {
                return candidate
            }
            index += 1
        }
    }

    private func migrateShortcutUsageHistoryIfNeeded(defaultProfileID: String) {
        guard !defaultProfileID.isEmpty else { return }

        let profilePrefixes = Set(profiles.map { "\($0.id)|" })
        var migratedUsageByDay: [String: [String: Int]] = [:]
        var didMigrate = false

        for (usageKey, dayUsage) in shortcutUsageByDay {
            if profilePrefixes.contains(where: { usageKey.hasPrefix($0) }) {
                migratedUsageByDay[usageKey] = dayUsage
                continue
            }

            let migratedKey = "\(defaultProfileID)|\(usageKey)"
            migratedUsageByDay[migratedKey, default: [:]].merge(dayUsage, uniquingKeysWith: +)
            didMigrate = true
        }

        guard didMigrate else { return }
        shortcutUsageByDay = migratedUsageByDay
        pruneAndPersistShortcutUsageByDay()
    }

    func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                statusMessage = L10n.tr("status.launch_at_login_enabled")
            } else {
                try SMAppService.mainApp.unregister()
                statusMessage = L10n.tr("status.launch_at_login_disabled")
            }
            launchAtLoginEnabled = enabled
        } catch {
            syncLaunchAtLoginStatus()
            launchErrorMessage = L10n.format("error.launch_at_login_failed", error.localizedDescription)
        }
    }

    func setKeyUsage(useNumberKeys: Bool, useFunctionKeys: Bool) {
        self.useNumberKeys = useNumberKeys
        self.useFunctionKeys = useFunctionKeys
        keyUsageDefaults.set(useNumberKeys, forKey: "settings.useNumberKeys")
        keyUsageDefaults.set(useFunctionKeys, forKey: "settings.useFunctionKeys")
    }

    func setDockIconVisible(_ visible: Bool) {
        guard showDockIcon != visible else { return }
        showDockIcon = visible
        keyUsageDefaults.set(visible, forKey: showDockIconDefaultsKey)
        applyDockIconVisibility()
    }

    func recordAndLaunch(_ shortcut: AppShortcut) {
        guard isShortcutAllowed(shortcut), !isHotKeysPaused else { return }
        guard launch(shortcut) else { return }
        recordShortcutUsage(for: shortcut)
    }

    @discardableResult
    func launch(_ shortcut: AppShortcut) -> Bool {
        prunePendingLaunches()

        let targetBundleIdentifier = shortcut.bundleIdentifier
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let frontmostBundleIdentifier = frontmostApp?.bundleIdentifier
        let targetRunningApp = runningApp(bundleIdentifier: targetBundleIdentifier)
        let targetHasVisibleWindow = targetRunningApp.map(hasVisibleWindow(for:)) ?? false

        if targetRunningApp != nil {
            clearPendingLaunch(for: targetBundleIdentifier)
        }

        if frontmostBundleIdentifier == targetBundleIdentifier {
            if let targetRunningApp {
                if !targetHasVisibleWindow {
                    reopenApplication(shortcut, remainingRetryCount: 1)
                    return true
                }

                if targetRunningApp.hide() {
                    launchErrorMessage = nil
                    return true
                }
            }
            _ = activateFallbackApplication(excluding: targetBundleIdentifier)
            launchErrorMessage = nil
            return true
        }

        if let frontmostBundleIdentifier,
           frontmostBundleIdentifier != targetBundleIdentifier,
           frontmostBundleIdentifier != appBundleIdentifier {
            lastForegroundBundleByTarget[targetBundleIdentifier] = frontmostBundleIdentifier
            rememberForegroundBundle(frontmostBundleIdentifier)
        }

        if let targetRunningApp {
            activateRunningApplication(shortcut, runningApp: targetRunningApp, remainingRetryCount: 1)
            return true
        }

        guard beginPendingLaunch(for: targetBundleIdentifier) else {
            launchErrorMessage = nil
            return false
        }

        reopenApplication(shortcut, remainingRetryCount: 1)
        return true
    }

    private func runningApp(bundleIdentifier: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first(where: { !$0.isTerminated })
    }

    private func syncLaunchAtLoginStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func startTrackingForegroundApps() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            guard let bundleIdentifier = app.bundleIdentifier else {
                return
            }
            guard bundleIdentifier != self.appBundleIdentifier else {
                return
            }

            self.clearPendingLaunch(for: bundleIdentifier)
            self.rememberForegroundBundle(bundleIdentifier)
        }
    }

    private func rememberForegroundBundle(_ bundleIdentifier: String) {
        recentForegroundBundles.removeAll { $0 == bundleIdentifier }
        recentForegroundBundles.append(bundleIdentifier)
        if recentForegroundBundles.count > 30 {
            recentForegroundBundles.removeFirst(recentForegroundBundles.count - 30)
        }
    }

    private func previousForegroundBundle(excluding targetBundleIdentifier: String) -> String? {
        recentForegroundBundles.reversed().first {
            $0 != targetBundleIdentifier && $0 != appBundleIdentifier
        }
    }

    private func bindHotKeyHandler() {
        HotKeyManager.shared.onHotKeyPressed = { [weak self] shortcut in
            Task { @MainActor in
                guard let self else { return }
                self.recordAndLaunch(shortcut)
            }
        }
    }

    private func activateRunningApplication(
        _ shortcut: AppShortcut,
        runningApp: NSRunningApplication,
        remainingRetryCount: Int
    ) {
        let didActivate = runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        guard didActivate else {
            reopenApplication(shortcut, remainingRetryCount: remainingRetryCount)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if frontmostBundleIdentifier == shortcut.bundleIdentifier {
                self.clearPendingLaunch(for: shortcut.bundleIdentifier)
                self.launchErrorMessage = nil
                return
            }

            // Avoid sending a second "open app" request while the app process already exists.
            // Re-activating the running app is safer and prevents duplicate windows/instances.
            if let refreshedRunningApp = self.runningApp(bundleIdentifier: shortcut.bundleIdentifier) {
                guard remainingRetryCount > 0 else {
                    self.clearPendingLaunch(for: shortcut.bundleIdentifier)
                    self.launchErrorMessage = L10n.format("error.app_launch_failed", shortcut.localizedName, "activation timeout")
                    return
                }
                self.activateRunningApplication(
                    shortcut,
                    runningApp: refreshedRunningApp,
                    remainingRetryCount: remainingRetryCount - 1
                )
                return
            }

            guard remainingRetryCount > 0 else {
                self.clearPendingLaunch(for: shortcut.bundleIdentifier)
                self.launchErrorMessage = L10n.format("error.app_launch_failed", shortcut.localizedName, "activation timeout")
                return
            }

            self.reopenApplication(shortcut, remainingRetryCount: remainingRetryCount - 1)
        }
    }

    private func reopenApplication(_ shortcut: AppShortcut, remainingRetryCount: Int) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: shortcut.bundleIdentifier) else {
            clearPendingLaunch(for: shortcut.bundleIdentifier)
            launchErrorMessage = L10n.format("error.app_not_found", shortcut.localizedName, shortcut.bundleIdentifier)
            return
        }
        openApplication(shortcut: shortcut, appURL: appURL, remainingRetryCount: remainingRetryCount)
    }

    @discardableResult
    private func activateFallbackApplication(excluding targetBundleIdentifier: String) -> Bool {
        var candidateBundleIdentifiers: [String] = []
        if let cachedPreviousBundle = lastForegroundBundleByTarget[targetBundleIdentifier] {
            candidateBundleIdentifiers.append(cachedPreviousBundle)
        }
        if let recentPreviousBundle = previousForegroundBundle(excluding: targetBundleIdentifier) {
            candidateBundleIdentifiers.append(recentPreviousBundle)
        }
        candidateBundleIdentifiers.append("com.apple.finder")

        var seenBundleIdentifiers = Set<String>()
        for bundleIdentifier in candidateBundleIdentifiers {
            guard
                !seenBundleIdentifiers.contains(bundleIdentifier),
                bundleIdentifier != targetBundleIdentifier,
                bundleIdentifier != appBundleIdentifier
            else {
                continue
            }
            seenBundleIdentifiers.insert(bundleIdentifier)

            if let candidateApp = runningApp(bundleIdentifier: bundleIdentifier),
               candidateApp.activate(options: [.activateIgnoringOtherApps]) {
                return true
            }

            if bundleIdentifier == "com.apple.finder",
               let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: finderURL, configuration: configuration) { _, _ in }
                return true
            }
        }

        return false
    }

    private func hasVisibleWindow(for app: NSRunningApplication) -> Bool {
        guard
            let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else {
            return true
        }

        return windowInfoList.contains { windowInfo in
            guard
                let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? NSNumber,
                ownerPID.int32Value == app.processIdentifier
            else {
                return false
            }

            let windowLayer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            return windowLayer == 0
        }
    }

    private func openApplication(shortcut: AppShortcut, appURL: URL, remainingRetryCount: Int) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    guard remainingRetryCount > 0 else {
                        self.clearPendingLaunch(for: shortcut.bundleIdentifier)
                        self.launchErrorMessage = L10n.format("error.app_launch_failed", shortcut.localizedName, error.localizedDescription)
                        return
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.openApplication(
                            shortcut: shortcut,
                            appURL: appURL,
                            remainingRetryCount: remainingRetryCount - 1
                        )
                    }
                    return
                }

                self.launchErrorMessage = nil
            }
        }
    }

    private func beginPendingLaunch(for bundleIdentifier: String) -> Bool {
        let now = Date()
        if let pendingDate = pendingLaunchDatesByBundleIdentifier[bundleIdentifier],
           now.timeIntervalSince(pendingDate) < pendingLaunchSuppressionInterval {
            return false
        }

        pendingLaunchDatesByBundleIdentifier[bundleIdentifier] = now
        return true
    }

    private func clearPendingLaunch(for bundleIdentifier: String) {
        pendingLaunchDatesByBundleIdentifier.removeValue(forKey: bundleIdentifier)
    }

    private func prunePendingLaunches(referenceDate: Date = Date()) {
        pendingLaunchDatesByBundleIdentifier = pendingLaunchDatesByBundleIdentifier.filter { _, pendingDate in
            referenceDate.timeIntervalSince(pendingDate) < pendingLaunchSuppressionInterval
        }
    }

    private func applyHotKeyRegistration() {
        let registrationState = HotKeyManager.shared.start(shortcuts: isHotKeysPaused ? [] : shortcuts)
        registrationWarnings = registrationState.warnings
        unavailableShortcutIDs = registrationState.unavailableShortcutIDs
    }

    private func loadHotKeyPauseState() {
        hotKeysPaused = keyUsageDefaults.bool(forKey: hotKeysPausedDefaultsKey)
    }

    private func loadKeyUsageSettings() {
        if keyUsageDefaults.object(forKey: "settings.useNumberKeys") != nil {
            useNumberKeys = keyUsageDefaults.bool(forKey: "settings.useNumberKeys")
        } else {
            useNumberKeys = false
            keyUsageDefaults.set(false, forKey: "settings.useNumberKeys")
        }
        if keyUsageDefaults.object(forKey: "settings.useFunctionKeys") != nil {
            useFunctionKeys = keyUsageDefaults.bool(forKey: "settings.useFunctionKeys")
        } else {
            useFunctionKeys = false
            keyUsageDefaults.set(false, forKey: "settings.useFunctionKeys")
        }
    }

    private func loadDockIconSetting() {
        if keyUsageDefaults.object(forKey: showDockIconDefaultsKey) != nil {
            showDockIcon = keyUsageDefaults.bool(forKey: showDockIconDefaultsKey)
        } else {
            showDockIcon = false
            keyUsageDefaults.set(false, forKey: showDockIconDefaultsKey)
        }
        applyDockIconVisibility()
    }

    private func applyDockIconVisibility() {
        let targetPolicy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            _ = NSApp.setActivationPolicy(targetPolicy)
        }
    }

    private func loadShortcutUsageCounts() {
        if let storedUsageByDay = keyUsageDefaults.dictionary(forKey: shortcutUsageByDayDefaultsKey) {
            shortcutUsageByDay = parseShortcutUsageByDay(storedUsageByDay)
            pruneAndPersistShortcutUsageByDay()
            return
        }

        guard let legacyUsage = keyUsageDefaults.dictionary(forKey: shortcutUsageLegacyDefaultsKey) else {
            shortcutUsageByDay = [:]
            return
        }

        let parsedLegacyUsage = parseLegacyUsageCounts(legacyUsage)
        guard !parsedLegacyUsage.isEmpty else {
            shortcutUsageByDay = [:]
            keyUsageDefaults.removeObject(forKey: shortcutUsageLegacyDefaultsKey)
            return
        }

        let todayKey = usageDayKey(for: Date())
        shortcutUsageByDay = parsedLegacyUsage.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = [todayKey: entry.value]
        }
        keyUsageDefaults.removeObject(forKey: shortcutUsageLegacyDefaultsKey)
        pruneAndPersistShortcutUsageByDay()
    }

    private func recordShortcutUsage(for shortcut: AppShortcut) {
        let usageKey = shortcutUsageKey(for: shortcut)
        let todayKey = usageDayKey(for: Date())
        var dayUsage = shortcutUsageByDay[usageKey, default: [:]]
        dayUsage[todayKey, default: 0] += 1
        shortcutUsageByDay[usageKey] = dayUsage
        pruneAndPersistShortcutUsageByDay()
        refreshTopShortcutUsages()
    }

    private func refreshTopShortcutUsages() {
        let validDayKeys = recentUsageDayKeys(referenceDate: Date())
        let rankedUsage = shortcuts
            .filter(\.enabled)
            .map { shortcut -> ShortcutUsageStat in
                let usageKey = shortcutUsageKey(for: shortcut)
                return ShortcutUsageStat(
                    id: usageKey,
                    shortcut: shortcut,
                    launchCount: usageCount(for: usageKey, validDayKeys: validDayKeys)
                )
            }
            .filter { $0.launchCount >= topUsageMinimumLaunchCount }
            .sorted { lhs, rhs in
                if lhs.launchCount == rhs.launchCount {
                    if lhs.shortcut.displayHotKey == rhs.shortcut.displayHotKey {
                        return lhs.shortcut.localizedName.localizedCaseInsensitiveCompare(rhs.shortcut.localizedName) == .orderedAscending
                    }
                    return lhs.shortcut.displayHotKey.localizedCompare(rhs.shortcut.displayHotKey) == .orderedAscending
                }
                return lhs.launchCount > rhs.launchCount
            }

        if rankedUsage.count < topUsageMinimumDisplayCount {
            topShortcutUsages = []
        } else {
            topShortcutUsages = Array(rankedUsage.prefix(topUsageDisplayLimit))
        }
    }

    func clearShortcutUsageHistory() {
        clearShortcutUsageHistory(forProfileID: activeProfileID)
        topShortcutUsages = []
        statusMessage = L10n.tr("status.usage_cleared")
    }

    private func clearShortcutUsageHistory(forProfileID profileID: String) {
        let prefix = "\(profileID)|"
        shortcutUsageByDay = shortcutUsageByDay.filter { !$0.key.hasPrefix(prefix) }
        if shortcutUsageByDay.isEmpty {
            keyUsageDefaults.removeObject(forKey: shortcutUsageByDayDefaultsKey)
            keyUsageDefaults.removeObject(forKey: shortcutUsageLegacyDefaultsKey)
        } else {
            pruneAndPersistShortcutUsageByDay()
        }
    }

    private func parseShortcutUsageByDay(_ storedUsageByDay: [String: Any]) -> [String: [String: Int]] {
        var parsedUsageByDay: [String: [String: Int]] = [:]

        for (usageKey, rawDayUsage) in storedUsageByDay {
            guard let rawDayMap = rawDayUsage as? [String: Any] else { continue }
            var parsedDayMap: [String: Int] = [:]
            for (dayKey, rawCount) in rawDayMap {
                if let count = rawCount as? Int, count > 0 {
                    parsedDayMap[dayKey] = count
                    continue
                }
                if let number = rawCount as? NSNumber {
                    let count = number.intValue
                    if count > 0 {
                        parsedDayMap[dayKey] = count
                    }
                }
            }
            if !parsedDayMap.isEmpty {
                parsedUsageByDay[usageKey] = parsedDayMap
            }
        }

        return parsedUsageByDay
    }

    private func parseLegacyUsageCounts(_ storedUsage: [String: Any]) -> [String: Int] {
        var parsedUsage: [String: Int] = [:]
        for (shortcutKey, rawCount) in storedUsage {
            if let count = rawCount as? Int, count > 0 {
                parsedUsage[shortcutKey] = count
                continue
            }
            if let number = rawCount as? NSNumber {
                let count = number.intValue
                if count > 0 {
                    parsedUsage[shortcutKey] = count
                }
            }
        }
        return parsedUsage
    }

    private func usageCount(for usageKey: String, validDayKeys: Set<String>) -> Int {
        guard let dayUsage = shortcutUsageByDay[usageKey] else { return 0 }
        var totalCount = 0
        for (dayKey, count) in dayUsage where validDayKeys.contains(dayKey) {
            totalCount += count
        }
        return totalCount
    }

    private func pruneAndPersistShortcutUsageByDay() {
        let validDayKeys = recentUsageDayKeys(referenceDate: Date())
        var prunedUsageByDay: [String: [String: Int]] = [:]

        for (usageKey, dayUsage) in shortcutUsageByDay {
            let filtered = dayUsage.filter { dayKey, count in
                count > 0 && validDayKeys.contains(dayKey)
            }
            if !filtered.isEmpty {
                prunedUsageByDay[usageKey] = filtered
            }
        }

        shortcutUsageByDay = prunedUsageByDay
        keyUsageDefaults.set(prunedUsageByDay, forKey: shortcutUsageByDayDefaultsKey)
    }

    private func recentUsageDayKeys(referenceDate: Date) -> Set<String> {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: referenceDate)
        return Set((0..<usageWindowDays).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: startOfToday) else { return nil }
            return usageDayKey(for: date)
        })
    }

    private func usageDayKey(for date: Date) -> String {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: startOfDay)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func isShortcutAllowed(_ shortcut: AppShortcut) -> Bool {
        let key = shortcut.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !useFunctionKeys, isFunctionKey(key) {
            return false
        }
        if !useNumberKeys, isNumberRowKey(key) {
            return false
        }
        return true
    }

    private func isFunctionKey(_ key: String) -> Bool {
        guard key.hasPrefix("f"), let number = Int(key.dropFirst()) else {
            return false
        }
        return (1...12).contains(number)
    }

    private func isNumberRowKey(_ key: String) -> Bool {
        guard let keyCode = ShortcutKeyMap.keyCode(for: key) else {
            return false
        }
        return numberRowKeyCodes.contains(keyCode)
    }

    private func startMonitoringShortcutFile() {
        stopMonitoringShortcutFile()

        let path = store.fileURL.path
        let fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return
        }

        monitoredFileDescriptor = fileDescriptor
        let monitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.main
        )

        monitor.setEventHandler { [weak self] in
            guard let self else { return }
            self.reloadShortcuts()
            if monitor.data.contains(.delete) || monitor.data.contains(.rename) {
                self.startMonitoringShortcutFile()
            }
        }

        monitor.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.monitoredFileDescriptor >= 0 {
                close(self.monitoredFileDescriptor)
                self.monitoredFileDescriptor = -1
            }
        }

        shortcutFileMonitor = monitor
        monitor.resume()
    }

    private func stopMonitoringShortcutFile() {
        shortcutFileMonitor?.cancel()
        shortcutFileMonitor = nil
    }

    private func normalizedModifiersFrom(_ modifiers: [ShortcutModifier]) -> [ShortcutModifier] {
        let modifierSet = Set(modifiers)
        return [.command, .option, .control, .shift].filter { modifierSet.contains($0) }
    }

    private func loadSystemShortcuts() -> [SystemShortcutEntry] {
        guard
            let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
            let symbolicHotKeys = domain["AppleSymbolicHotKeys"] as? [String: Any]
        else {
            return []
        }

        var entries: [SystemShortcutEntry] = []
        for (rawID, rawEntry) in symbolicHotKeys {
            guard
                let id = Int(rawID),
                let entry = rawEntry as? [String: Any],
                let enabled = intValue(from: entry["enabled"]),
                enabled == 1,
                let value = entry["value"] as? [String: Any],
                let parameters = value["parameters"] as? [Any],
                parameters.count >= 3,
                let keyCodeValue = intValue(from: parameters[1]),
                keyCodeValue >= 0,
                keyCodeValue != Int(UInt16.max),
                let modifiersMask = intValue(from: parameters[2])
            else {
                continue
            }

            entries.append(
                SystemShortcutEntry(
                    id: id,
                    keyCode: UInt32(keyCodeValue),
                    modifiers: modifiersFromSystemMask(modifiersMask)
                )
            )
        }

        return entries.sorted { $0.id < $1.id }
    }

    private func modifiersFromSystemMask(_ mask: Int) -> [ShortcutModifier] {
        let eventFlags = NSEvent.ModifierFlags(rawValue: UInt(mask))
        var modifiers: [ShortcutModifier] = []
        if eventFlags.contains(.command) {
            modifiers.append(.command)
        }
        if eventFlags.contains(.option) {
            modifiers.append(.option)
        }
        if eventFlags.contains(.control) {
            modifiers.append(.control)
        }
        if eventFlags.contains(.shift) {
            modifiers.append(.shift)
        }
        return normalizedModifiersFrom(modifiers)
    }

    private func intValue(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func shortcutUsageKey(for shortcut: AppShortcut) -> String {
        let normalizedKey = shortcut.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let modifierToken = normalizedModifiersFrom(shortcut.modifiers)
            .map(\.rawValue)
            .joined(separator: "+")
        return "\(activeProfileID)|\(modifierToken.isEmpty ? "none" : modifierToken)|\(normalizedKey)"
    }
}

private struct SystemShortcutEntry {
    let id: Int
    let keyCode: UInt32
    let modifiers: [ShortcutModifier]
}

struct ShortcutUsageStat: Identifiable, Hashable {
    let id: String
    let shortcut: AppShortcut
    let launchCount: Int
}
