import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let title: String
    let shortcut: AppShortcut
    let onRecord: (AppShortcut) -> Void
    let onInvalid: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.alignment = .center
        button.setButtonType(.momentaryPushIn)
        button.target = context.coordinator
        button.action = #selector(Coordinator.beginRecording(_:))
        button.onRecord = { shortcut in context.coordinator.record(shortcut) }
        button.onInvalid = { message in context.coordinator.invalid(message) }
        button.setAccessibilityLabel("Shortcut for \(title)")
        button.setAccessibilityHelp("Activate to record a new shortcut, then type a key combination.")
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        context.coordinator.parent = self
        button.onRecord = { shortcut in context.coordinator.record(shortcut) }
        button.onInvalid = { message in context.coordinator.invalid(message) }
        button.setAccessibilityLabel("Shortcut for \(title)")
        button.shortcut = shortcut
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ShortcutRecorder

        init(_ parent: ShortcutRecorder) {
            self.parent = parent
        }

        @objc func beginRecording(_ sender: ShortcutRecorderButton) {
            sender.beginRecording()
        }

        func record(_ shortcut: AppShortcut) {
            parent.onRecord(shortcut)
        }

        func invalid(_ message: String) {
            parent.onInvalid(message)
        }
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    var onRecord: ((AppShortcut) -> Void)?
    var onInvalid: ((String) -> Void)?
    var shortcut = AppShortcut(key: "1", modifiers: .command) {
        didSet { updateTitle() }
    }

    private var recording = false
    private var eventMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if !recording && (event.keyCode == 36 || event.keyCode == 49) {
            beginRecording()
            return
        }
        super.keyDown(with: event)
    }

    func beginRecording() {
        guard !recording else { return }
        recording = true
        title = "Type shortcut…"
        setAccessibilityValue("Recording")
        window?.makeFirstResponder(self)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording, self.window?.isKeyWindow == true else { return event }
            self.capture(event)
            return nil
        }
    }

    override func resignFirstResponder() -> Bool {
        endRecording()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { endRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    private func capture(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 && flags.intersection([.command, .option, .control, .shift]).isEmpty {
            endRecording()
            return
        }
        guard !event.isARepeat, let candidate = AppShortcut(event: event) else { return }
        guard candidate.hasPrimaryModifier else {
            onInvalid?(ShortcutAssignmentIssue.needsModifier.message)
            NSSound.beep()
            return
        }
        onRecord?(candidate)
        endRecording()
    }

    private func endRecording() {
        recording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        updateTitle()
    }

    private func updateTitle() {
        guard !recording else { return }
        title = shortcut.displayName
        setAccessibilityValue(shortcut.displayName)
    }

}
