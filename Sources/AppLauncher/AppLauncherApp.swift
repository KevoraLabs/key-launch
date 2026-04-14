import CoreServices
import SwiftUI

enum AppBuildFlavor {
    #if DEBUG
    static let isDebug = true
    #else
    static let isDebug = false
    #endif

    static var activeMenuBarSymbolName: String {
        isDebug ? "hammer.circle.fill" : "k.square.fill"
    }

    static var pausedMenuBarSymbolName: String {
        isDebug ? "pause.circle.fill" : "nosign.app.fill"
    }
}

enum AppVersion {
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var displayString: String {
        L10n.format("app.version", marketingVersion, buildNumber)
    }
}

@main
struct AppLauncherApp: App {
    @StateObject private var viewModel = AppLauncherViewModel()
    private let suppressInitialWindow = LaunchContext.launchedAsLoginItem

    var body: some Scene {
        Window(L10n.tr("app.name"), id: "main") {
            ContentView(viewModel: viewModel, suppressInitialWindow: suppressInitialWindow)
                .frame(width: 980, height: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window(L10n.tr("profiles.manage"), id: "profiles") {
            ProfileManagementView(viewModel: viewModel)
                .frame(width: 520, height: 420)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarPanel(viewModel: viewModel)
        } label: {
            Image(systemName: viewModel.isHotKeysPaused ? AppBuildFlavor.pausedMenuBarSymbolName : AppBuildFlavor.activeMenuBarSymbolName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 24, height: 24)
        }
        .menuBarExtraStyle(.menu)

        .commands {
            CommandMenu(L10n.tr("menu.shortcuts")) {
                Toggle(
                    L10n.tr("menu.launch_at_login"),
                    isOn: Binding(
                        get: { viewModel.launchAtLoginEnabled },
                        set: { viewModel.setLaunchAtLogin(enabled: $0) }
                    )
                )

                Toggle(
                    L10n.tr("menu.show_dock_icon"),
                    isOn: Binding(
                        get: { viewModel.showDockIcon },
                        set: { viewModel.setDockIconVisible($0) }
                    )
                )

                Divider()

                Button(viewModel.isHotKeysPaused ? L10n.tr("menu.resume_hotkeys") : L10n.tr("menu.pause_hotkeys")) {
                    if viewModel.isHotKeysPaused {
                        viewModel.resumeHotKeys()
                    } else {
                        viewModel.pauseHotKeys()
                    }
                }

                Divider()

                Button(L10n.tr("menu.import_shortcuts")) {
                    viewModel.importShortcuts()
                }

                Button(L10n.tr("menu.export_shortcuts")) {
                    viewModel.exportShortcuts()
                }
            }
        }
    }
}

private enum LaunchContext {
    static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }
        guard event.eventID == AEEventID(kAEOpenApplication) else {
            return false
        }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
    }
}

private struct MenuBarPanel: View {
    @ObservedObject var viewModel: AppLauncherViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                Label(L10n.format("menu.show_main_window", L10n.tr("app.name")), systemImage: "macwindow")
            }

            Toggle(
                isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLogin(enabled: $0) }
                )
            ) {
                Label(L10n.tr("menu.launch_at_login"), systemImage: "person.crop.circle.badge.checkmark")
            }

            Toggle(
                isOn: Binding(
                    get: { viewModel.showDockIcon },
                    set: { viewModel.setDockIconVisible($0) }
                )
            ) {
                Label(L10n.tr("menu.show_dock_icon"), systemImage: "dock.rectangle")
            }

            Divider()

            if viewModel.profiles.count > 1 {
                Menu {
                    ForEach(viewModel.profiles) { profile in
                        Button {
                            viewModel.selectProfile(id: profile.id)
                        } label: {
                            Label(
                                profile.name,
                                systemImage: viewModel.activeProfileID == profile.id ? "checkmark" : "circle"
                            )
                        }
                    }
                } label: {
                    Label(L10n.tr("profiles.switch"), systemImage: "arrow.triangle.2.circlepath")
                }

                Divider()
            }

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "profiles")
            } label: {
                Label(L10n.tr("profiles.manage"), systemImage: "slider.horizontal.3")
            }

            Divider()

            Button {
                if viewModel.isHotKeysPaused {
                    viewModel.resumeHotKeys()
                } else {
                    viewModel.pauseHotKeys()
                }
            } label: {
                Label(
                    viewModel.isHotKeysPaused ? L10n.tr("menu.resume_hotkeys") : L10n.tr("menu.pause_hotkeys"),
                    systemImage: viewModel.isHotKeysPaused ? "play.fill" : "pause.fill"
                )
            }

            Divider()

            Button {
                viewModel.importShortcuts()
            } label: {
                Label(L10n.tr("menu.import_shortcuts"), systemImage: "square.and.arrow.down")
            }

            Button {
                viewModel.exportShortcuts()
            } label: {
                Label(L10n.tr("menu.export_shortcuts"), systemImage: "square.and.arrow.up")
            }

            Divider()

            Text(AppVersion.displayString)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label(L10n.tr("menu.quit"), systemImage: "power")
            }
            .keyboardShortcut("q")
        }
    }
}

private struct ProfileManagementView: View {
    @ObservedObject var viewModel: AppLauncherViewModel
    @State private var profileNameDraft = ""
    @FocusState private var profileNameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("profiles.manage"))
                        .font(.title3.weight(.semibold))
                    Text(L10n.format("profiles.active_summary", viewModel.activeProfileName))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    viewModel.createProfile()
                } label: {
                    Label(L10n.tr("profiles.add"), systemImage: "plus")
                }
            }

            HStack(alignment: .top, spacing: 16) {
                profileList
                    .frame(width: 220)

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.tr("profiles.rename"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField(L10n.tr("profiles.rename_placeholder"), text: $profileNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($profileNameFieldFocused)
                        .onSubmit {
                            commitProfileNameDraft()
                        }

                    HStack(spacing: 8) {
                        Button(L10n.tr("assign.save")) {
                            commitProfileNameDraft()
                        }

                        Button(role: .destructive) {
                            viewModel.deleteActiveProfile()
                        } label: {
                            Label(L10n.tr("profiles.delete"), systemImage: "trash")
                        }
                        .disabled(!viewModel.canDeleteActiveProfile)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            syncProfileNameDraft()
        }
        .onChange(of: viewModel.activeProfileID) { _ in
            syncProfileNameDraft()
        }
        .onChange(of: profileNameFieldFocused) { isFocused in
            if !isFocused {
                commitProfileNameDraft()
            }
        }
    }

    private var profileList: some View {
        List {
            ForEach(viewModel.profiles) { profile in
                Button {
                    viewModel.selectProfile(id: profile.id)
                } label: {
                    profileRow(for: profile)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.inset)
    }

    private func profileRow(for profile: ShortcutProfile) -> some View {
        let isActive = viewModel.activeProfileID == profile.id

        return HStack(spacing: 8) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            Text(profile.name)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func syncProfileNameDraft() {
        if !profileNameFieldFocused {
            profileNameDraft = viewModel.activeProfileName
        }
    }

    private func commitProfileNameDraft() {
        let trimmedName = profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            profileNameDraft = viewModel.activeProfileName
            return
        }

        viewModel.renameActiveProfile(to: trimmedName)
        profileNameDraft = viewModel.activeProfileName
    }
}
