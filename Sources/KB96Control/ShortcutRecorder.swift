import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var drag: DragController

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onBegin = { drag.beginShortcutRecording() }
        button.onFinish = { shortcut in drag.finishShortcutRecording(shortcut) }
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.shortcutName = drag.key.displayName
        if !button.recording { button.title = "\(button.shortcutName) — click to record" }
    }

    static func dismantleNSView(_ button: RecorderButton, coordinator: ()) { button.finish(nil) }
}

final class RecorderButton: NSButton {
    var onBegin: (() -> Void)?
    var onFinish: ((DragShortcut?) -> Void)?
    var shortcutName = ""
    private(set) var recording = false
    private var monitor: Any?
    private var observer: NSObjectProtocol?
    private var candidate: DragShortcut?

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(begin)
        setAccessibilityLabel("Drag shortcut recorder")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func begin() {
        if recording { finish(nil); return }
        recording = true
        candidate = nil
        onBegin?()
        title = "Press and release a key… (Esc cancels)"
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown]) { [weak self] event in
            guard let self, self.recording else { return event }
            guard self.window?.isKeyWindow == true else { self.finish(nil); return event }
            if event.type == .leftMouseDown {
                if !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) { self.finish(nil) }
                return event
            }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.finish(nil); return nil }
                if !event.isARepeat {
                    self.candidate = DragShortcut.recording(event)
                    self.title = self.candidate.map { "Release \($0.displayName) to save" } ?? "Choose a holdable key (Esc cancels)"
                }
            } else if event.type == .keyUp, self.candidate?.code == event.keyCode {
                self.finish(self.candidate)
            } else if event.type == .flagsChanged {
                if let candidate = self.candidate, candidate.modifierFlag != nil, candidate.code == event.keyCode {
                    if !CGEventSource.keyState(.combinedSessionState, key: event.keyCode) { self.finish(candidate) }
                } else if self.candidate == nil && CGEventSource.keyState(.combinedSessionState, key: event.keyCode) {
                    self.candidate = DragShortcut.recording(event)
                }
            }
            return nil
        }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.finish(nil)
        }
    }

    func finish(_ shortcut: DragShortcut?) {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        candidate = nil
        onFinish?(shortcut)
        title = "\(shortcutName) — click to record"
    }
}
