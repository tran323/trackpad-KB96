import AppKit
import SwiftUI
import Combine

@main
enum KB96ControlApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let drag = DragController()
    private let inspector = HIDInspector()
    private let loginItem = LoginItemController()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit KB96 Control", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        drag.$enabled.combineLatest(drag.$dragging).sink { [weak self] enabled, dragging in
            self?.updateMenu(enabled: enabled, dragging: dragging)
        }.store(in: &subscriptions)

        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                self?.drag.stop()
                self?.inspector.stopCapture()
            })
        }
        loginItem.configureOnFirstLaunch()
        drag.startAtLaunch()
        showSettings()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        loginItem.refresh()
        drag.refreshAccessibility()
    }

    private func updateMenu(enabled: Bool, dragging: Bool) {
        statusItem.button?.title = dragging ? "KB96 • Drag" : (enabled ? "KB96 • On" : "KB96")
        let menu = NSMenu()
        let toggle = menu.addItem(withTitle: enabled ? "Disable Drag Helper" : "Enable Drag Helper",
                                  action: #selector(toggleDrag), keyEquivalent: "")
        toggle.target = self
        menu.addItem(withTitle: "Release and Disable", action: #selector(releaseAndDisable), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings and HID Inspector…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit KB96 Control", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func toggleDrag() { if drag.enabled { drag.stop() } else { drag.start() } }
    @objc private func releaseAndDisable() { drag.stop() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showSettings() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "KB96 Control"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 700, height: 570)
            window.contentView = NSHostingView(rootView: SettingsView(drag: drag, inspector: inspector, loginItem: loginItem))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        drag.shutdown()
        inspector.shutdown()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

struct SettingsView: View {
    @ObservedObject var drag: DragController
    @ObservedObject var inspector: HIDInspector
    @ObservedObject var loginItem: LoginItemController

    var body: some View {
        TabView {
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Make dragging easier").font(.largeTitle.bold())
                Text("Hold your chosen key or shortcut, move your Jomaa trackpad, then release to drop.")
                HStack {
                    Text("Hold to drag")
                    ShortcutRecorder(drag: drag).frame(width: 360, height: 28)
                }
                Text("Click the input, then press and release a key or combination. Letters, Space, arrows, function keys and individual modifier keys are supported. Escape cancels; Caps Lock and media-only keys cannot be used.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Enable drag helper", isOn: Binding(
                    get: { drag.enabled },
                    set: { if $0 { drag.start() } else { drag.stop() } }
                ))
                Text(drag.status).font(.headline).textSelection(.enabled)
                Divider()
                Text("Use it in Finder, for text selection, or after Command + Shift + 4 for screenshot area selection. Position the pointer first, then hold the drag key.")
                Text("Escape releases the drag. Control + Option + Command + Escape releases and disables the helper. A held drag releases automatically after 60 seconds.")
                Text("The shortcut is reserved while the helper is enabled, including in other apps. A plain letter or Space will not type while assigned. Other shortcuts pass through. The helper works with every pointing device and disables after sleep.")
                    .foregroundStyle(.secondary)
                HStack {
                    if drag.accessibilityGranted {
                        Label("Accessibility granted", systemImage: "checkmark.circle")
                    } else {
                        Button("Grant Accessibility…") { drag.requestAccessibility() }
                    }
                    Button("Input Monitoring Settings…") { openInputSettings() }
                    Button("Release and Disable") { drag.stop() }
                }
                Spacer()
                Text("This first version uses the trackpad’s existing mouse input. Custom finger gestures need device captures from your Mac.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(28)
            }
            .tabItem { Label("Drag Helper", systemImage: "cursorarrow.motionlines") }

            GestureSettingsView(settings: drag.gestures, drag: drag)
                .tabItem { Label("Gestures", systemImage: "hand.draw") }

            VStack(alignment: .leading, spacing: 12) {
                Text("Jomaa HID Inspector").font(.title2.bold())
                Text("Scan, select your trackpad, then capture. JOMAA / KB96 name matches appear first. A device may have several interfaces; capture them separately.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Scan Devices") { inspector.scan() }.disabled(inspector.capturing)
                    Picker("Device", selection: $inspector.selectedID) {
                        Text("Select an interface").tag(Optional<UInt64>.none)
                        ForEach(inspector.devices) { device in
                            Text(device.label).tag(Optional(device.id))
                        }
                    }.disabled(inspector.capturing)
                }
                if let device = inspector.selected {
                    Text(device.details).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                TextField("Gesture to capture, e.g. two-finger tap", text: $inspector.gestureLabel)
                    .disabled(inspector.capturing)
                HStack {
                    Button(inspector.capturing ? "Stop Capture" : "Start Capture") {
                        if inspector.capturing { inspector.stopCapture() } else { inspector.startCapture() }
                    }.disabled(inspector.selected == nil)
                    Button("Clear Log") { inspector.clear() }
                    Button("Export Diagnostics…") { inspector.export() }
                    Button("Input Monitoring…") { openInputSettings() }
                }
                Text(inspector.status).font(.callout).textSelection(.enabled)
                TabView {
                    logView(inspector.log.isEmpty ? "No input captured yet. Move, tap, press, drag or scroll on the selected device." : inspector.log)
                        .tabItem { Text("Live Input") }
                    logView(inspector.descriptor.isEmpty ? "Start a capture to enumerate the selected interface’s elements." : inspector.descriptor)
                        .tabItem { Text("HID Elements") }
                }
                Text("Captures include raw input from the selected interface. If it is a keyboard interface, keystroke codes can appear in the export. Capture only the trackpad gestures you want to inspect.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem { Label("HID Inspector", systemImage: "waveform.path") }

            VStack(alignment: .leading, spacing: 20) {
                Text("Startup").font(.largeTitle.bold())
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.enabled },
                    set: { loginItem.setEnabled($0) }
                ))
                Text(loginItem.status).textSelection(.enabled)
                if loginItem.requiresApproval {
                    Button("Open Login Items Settings…") { loginItem.openLoginItems() }
                }
                Toggle("Enable drag helper at launch", isOn: $drag.enableAtLaunch)
                Text("The drag helper enables automatically at launch once Accessibility access is granted. Release and Disable keeps it off for the rest of the session; turn off this setting to keep it off on future launches too.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(28)
            .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding(8)
    }

    private func logView(_ text: String) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text).font(.system(.caption, design: .monospaced))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(10)
        }.background(Color(nsColor: .textBackgroundColor))
    }

    private func openInputSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
