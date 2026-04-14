import Foundation

struct ShortcutProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var shortcuts: [AppShortcut]

    init(
        id: String = UUID().uuidString,
        name: String,
        shortcuts: [AppShortcut] = []
    ) {
        self.id = id
        self.name = name
        self.shortcuts = shortcuts
    }
}

struct ShortcutProfilesDocument: Codable, Hashable {
    var activeProfileID: String
    var profiles: [ShortcutProfile]

    init(activeProfileID: String, profiles: [ShortcutProfile]) {
        self.activeProfileID = activeProfileID
        self.profiles = profiles
    }

    var activeProfile: ShortcutProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    var totalShortcutCount: Int {
        profiles.reduce(0) { $0 + $1.shortcuts.count }
    }

    func normalized() -> ShortcutProfilesDocument {
        var usedIDs = Set<String>()
        let normalizedProfiles = profiles.enumerated().map { index, profile -> ShortcutProfile in
            let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            var normalizedProfile = profile

            if normalizedProfile.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || usedIDs.contains(normalizedProfile.id) {
                normalizedProfile.id = UUID().uuidString
            }
            usedIDs.insert(normalizedProfile.id)

            if trimmedName.isEmpty {
                normalizedProfile.name = Self.fallbackProfileName(at: index)
            }

            return normalizedProfile
        }

        let fallbackProfiles = normalizedProfiles.isEmpty
            ? [ShortcutProfile(name: Self.fallbackProfileName(at: 0), shortcuts: ShortcutStore.defaultShortcuts)]
            : normalizedProfiles
        let resolvedActiveProfileID = fallbackProfiles.contains(where: { $0.id == activeProfileID })
            ? activeProfileID
            : fallbackProfiles[0].id

        return ShortcutProfilesDocument(activeProfileID: resolvedActiveProfileID, profiles: fallbackProfiles)
    }

    static func fallbackProfileName(at index: Int) -> String {
        if index == 0 {
            return L10n.tr("profiles.default_name")
        }
        return L10n.format("profiles.auto_name", index + 1)
    }
}

struct ShortcutStore {
    let fileURL: URL
    private let fileManager = FileManager.default

    private static let legacyDirectoryName = "AppLauncher"
    private static let productionBundleIdentifier = "com.kevinxft.keylaunch"

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let directory = (appSupport ?? URL(fileURLWithPath: NSHomeDirectory()))
                .appendingPathComponent(Self.storageDirectoryName, isDirectory: true)
            self.fileURL = directory.appendingPathComponent("shortcuts.json", isDirectory: false)
        }
    }

    func loadDocument() throws -> ShortcutProfilesDocument {
        try ensureConfigExists()
        let data = try Data(contentsOf: fileURL)
        return try decodeDocument(from: data)
    }

    func saveDocument(_ document: ShortcutProfilesDocument) throws {
        try ensureDirectoryExists()
        try write(document.normalized())
    }

    func decodeDocument(from data: Data) throws -> ShortcutProfilesDocument {
        let decoder = JSONDecoder()
        if let document = try? decoder.decode(ShortcutProfilesDocument.self, from: data) {
            return document.normalized()
        }

        let shortcuts = try decoder.decode([AppShortcut].self, from: data)
        return ShortcutProfilesDocument(
            activeProfileID: "default",
            profiles: [
                ShortcutProfile(
                    id: "default",
                    name: ShortcutProfilesDocument.fallbackProfileName(at: 0),
                    shortcuts: shortcuts
                )
            ]
        ).normalized()
    }

    private func ensureConfigExists() throws {
        try ensureDirectoryExists()
        try migrateLegacyConfigIfNeeded()
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try write(Self.defaultDocument)
    }

    private func ensureDirectoryExists() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func migrateLegacyConfigIfNeeded() throws {
        guard Self.shouldMigrateLegacyConfig,
              !fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        let legacyURL = Self.legacyFileURL
        guard fileManager.fileExists(atPath: legacyURL.path) else {
            return
        }

        try fileManager.copyItem(at: legacyURL, to: fileURL)
    }

    private func write(_ document: ShortcutProfilesDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])
    }

    static let defaultShortcuts: [AppShortcut] = [
        AppShortcut(
            id: "safari",
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            key: "s",
            modifiers: [.option]
        ),
        AppShortcut(
            id: "finder",
            name: "Finder",
            bundleIdentifier: "com.apple.finder",
            key: "f",
            modifiers: [.option]
        )
    ]

    private static var defaultDocument: ShortcutProfilesDocument {
        ShortcutProfilesDocument(
            activeProfileID: "default",
            profiles: [
                ShortcutProfile(
                    id: "default",
                    name: ShortcutProfilesDocument.fallbackProfileName(at: 0),
                    shortcuts: defaultShortcuts
                )
            ]
        )
    }

    private static var storageDirectoryName: String {
        Bundle.main.bundleIdentifier ?? "KeyLaunch"
    }

    private static var shouldMigrateLegacyConfig: Bool {
        Bundle.main.bundleIdentifier == productionBundleIdentifier
    }

    private static var legacyFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directory = (appSupport ?? URL(fileURLWithPath: NSHomeDirectory()))
            .appendingPathComponent(legacyDirectoryName, isDirectory: true)
        return directory.appendingPathComponent("shortcuts.json", isDirectory: false)
    }
}
