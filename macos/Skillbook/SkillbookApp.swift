import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.requestQuit() { return .terminateNow }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct SkillKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel(backend: RustBackend())
    @State private var shortcuts = ShortcutSettings()
    @State private var applicationUpdater = ApplicationUpdater()

    var body: some Scene {
        WindowGroup {
            SkillbookRootView()
            .environment(model)
            .environment(shortcuts)
            .environment(applicationUpdater)
            .frame(minWidth: 880, minHeight: 580)
            .background(SkillbookTheme.surface(.one))
            .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            SettingsWindowCommands {
                NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
            }
            CommandGroup(replacing: .newItem) {
                if model.onboardingComplete {
                    Button("New Skill…") { model.showNewSkillSheet = true }
                        .keyboardShortcut(shortcuts.shortcut(for: .newSkill).keyboardShortcut)
                    Button("Install Skill…") { model.showInstallSheet = true }
                        .keyboardShortcut(shortcuts.shortcut(for: .installSkill).keyboardShortcut)
                }
            }
            CommandGroup(after: .appInfo) {
                Button(applicationUpdater.primaryActionTitle) {
                    applicationUpdater.performPrimaryAction()
                }
                .disabled(!applicationUpdater.canPerformPrimaryAction)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { model.save() }
                    .keyboardShortcut(shortcuts.shortcut(for: .save).keyboardShortcut)
                    .disabled(!model.onboardingComplete || !model.dirty)
            }
            if model.onboardingComplete {
                CommandMenu("Skill") {
                    Button("Open in Default App") { model.openInDefaultApp() }
                        .keyboardShortcut(shortcuts.shortcut(for: .openInDefaultApp).keyboardShortcut)
                        .disabled(model.selected == nil)
                    Button("Open in Finder") { model.revealInFinder() }
                        .keyboardShortcut(shortcuts.shortcut(for: .revealInFinder).keyboardShortcut)
                        .disabled(model.selected == nil)
                    Button("Open GitHub") { model.openGitHub() }
                        .disabled(model.selected?.githubUrl == nil)
                    Button("Copy Path") { model.copyPath() }
                        .disabled(model.selected == nil)
                    Button("Copy skills.sh command") { model.copyNpx() }
                        .disabled(model.selected?.npxInstall == nil)
                    Button("Show Skill Locations") { model.presentSkillLocations() }
                        .keyboardShortcut(shortcuts.shortcut(for: .showLocations).keyboardShortcut)
                        .disabled(model.selected == nil)
                    Button("Use in Project…") { model.presentUseInProject() }
                        .disabled(model.selected == nil)
                    Button("Duplicate Checker…") { model.showDuplicateSheet = true }
                    Divider()
                    Button("Update") {
                        if let id = model.selectedId { model.updateOne(id) }
                    }
                    .disabled(!(model.selected?.canUpdate ?? false) || model.updating)
                    Divider()
                    Button("Move to Trash…") { model.requestDelete() }
                        .disabled(model.selected == nil)
                }
            }
            CommandGroup(after: .sidebar) {
                if model.onboardingComplete {
                    ViewModeMenuItems(selection: Binding(
                        get: { model.viewMode },
                        set: { model.viewMode = $0 }
                    ), shortcuts: shortcuts)
                    Divider()
                    Button("Search Skills") { model.searchPresented = true }
                        .keyboardShortcut(shortcuts.shortcut(for: .searchSkills).keyboardShortcut)
                    Divider()
                    Button("Reload Skills") { model.rescan(silent: false) }
                        .keyboardShortcut(shortcuts.shortcut(for: .reloadSkills).keyboardShortcut)
                    Button(model.availableUpdateCount > 0 ? "Review Skill Updates…" : "Check for Skill Updates…") {
                        model.reviewFetchedUpdates()
                    }
                        .keyboardShortcut(shortcuts.shortcut(for: .checkForUpdates).keyboardShortcut)
                        .disabled(model.busy)
                }
            }
        }

        Window("SkillKit Settings", id: "settings") {
            Group {
                if model.onboardingComplete {
                    SettingsView()
                } else {
                    SetupRequiredSettingsView()
                }
            }
            .environment(model)
            .environment(shortcuts)
            .environment(applicationUpdater)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            SettingsWindowCommands {
                NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
            }
        }
    }
}

private struct SettingsWindowCommands: Commands {
    let openSettings: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…", action: openSettings)
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

private struct SkillbookRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if model.onboardingComplete {
                WorkspaceView()
                    .transition(workspaceTransition)
            } else {
                OnboardingView()
                    .transition(workspaceTransition)
            }
        }
        .animation(workspaceAnimation, value: model.onboardingComplete)
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsWindow)) { _ in
            openWindow(id: "settings")
        }
    }

    private var workspaceTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.99))
    }

    private var workspaceAnimation: Animation {
        reduceMotion
            ? .timingCurve(0.23, 1, 0.32, 1, duration: 0.16)
            : .timingCurve(0.23, 1, 0.32, 1, duration: 0.24)
    }
}

private extension Notification.Name {
    static let openSettingsWindow = Notification.Name("openSettingsWindow")
}
