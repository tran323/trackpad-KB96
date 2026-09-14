import AppKit
import ApplicationServices
import Combine

/// All callbacks and state changes run on the main run loop.
final class DragController: ObservableObject {
    let gestures = GestureSettings()
    private var pointerRemapper = PointerRemapper()
    @Published private(set) var enabled = false
    @Published private(set) var dragging = false
    @Published private(set) var status = "Drag helper is off."
    @Published private(set) var accessibilityGranted = false
    @Published var enableAtLaunch: Bool {
        didSet { UserDefaults.standard.set(enableAtLaunch, forKey: "enableDragAtLaunch") }
    }
    @Published private(set) var key: DragShortcut
    private var resumeAfterRecording = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var deadline: Timer?
    private var permissionTimer: Timer?
    private var waitingForAccessibility = false
    private var held = false
    private var swallowLeftUp = false
    private var swallowedKeys = Set<CGKeyCode>()
    private let marker: Int64 = 0x4B423936
    private let eventSource = CGEventSource(stateID: .privateState)

    init() {
        key = DragShortcut.load(from: .standard)
        enableAtLaunch = UserDefaults.standard.object(forKey: "enableDragAtLaunch") as? Bool ?? true
    }

    func beginShortcutRecording() {
        let resume = enabled || waitingForAccessibility
        stop()
        resumeAfterRecording = resume
    }

    func finishShortcutRecording(_ shortcut: DragShortcut?) {
        if let shortcut, shortcut.isValid, let data = try? JSONEncoder().encode(shortcut) {
            key = shortcut
            UserDefaults.standard.set(data, forKey: "dragShortcut")
        }
        let resume = resumeAfterRecording
        resumeAfterRecording = false
        if resume { start(promptForAccessibility: false) }
    }

    func startAtLaunch() {
        refreshAccessibility()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshAccessibility()
        }
        permissionTimer?.invalidate()
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        if enableAtLaunch { start(promptForAccessibility: false) }
    }

    func refreshAccessibility() {
        let trusted = AXIsProcessTrusted()
        if accessibilityGranted != trusted { accessibilityGranted = trusted }
        if !trusted && enabled {
            stop()
            status = "Accessibility access was removed. Allow access, then enable the helper again."
        } else if trusted && waitingForAccessibility {
            start(promptForAccessibility: false)
        }
    }

    func requestAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
        guard !accessibilityGranted else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func start(promptForAccessibility: Bool = true) {
        guard !enabled else { return }
        accessibilityGranted = AXIsProcessTrusted()
        guard accessibilityGranted else {
            waitingForAccessibility = true
            if promptForAccessibility { requestAccessibility() }
            status = "Waiting for Accessibility access. The helper will enable when access is granted."
            return
        }
        waitingForAccessibility = false
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged, .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: { proxy, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<DragController>.fromOpaque(context).takeUnretainedValue()
                let synthetic = event.getIntegerValueField(.eventSourceUserData) == owner.marker
                guard let result = owner.handle(proxy: proxy, type: type, event: event) else { return nil }
                guard !synthetic else { return result }
                return owner.pointerRemapper.handle(result.takeUnretainedValue(), settings: owner.gestures)
                    .map { Unmanaged.passUnretained($0) }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            status = "Cannot monitor input. Check Accessibility and Input Monitoring, then reopen the app."
            return
        }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            status = "Could not create the input listener."
            return
        }
        tap = newTap
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        enabled = true
        status = "Hold \(key.displayName) to drag; release to drop."
    }

    func stop() {
        resumeAfterRecording = false
        waitingForAccessibility = false
        releaseDrag()
        for event in pointerRemapper.releaseEvents() {
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cgSessionEventTap)
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        held = false
        swallowLeftUp = false
        swallowedKeys.removeAll()
        enabled = false
        status = "Drag helper is off."
    }

    func shutdown() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        stop()
    }

    private func emit(_ type: CGEventType, at point: CGPoint, flags: CGEventFlags,
                      proxy: CGEventTapProxy? = nil) -> Bool {
        guard let event = CGEvent(mouseEventSource: eventSource, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return false }
        event.flags = key.mouseFlags(flags)
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        if let proxy {
            event.tapPostEvent(proxy)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
        return true
    }

    private func releaseDrag(proxy: CGEventTapProxy? = nil, event: CGEvent? = nil) {
        deadline?.invalidate()
        deadline = nil
        guard dragging else { return }
        let current = event ?? CGEvent(source: nil)
        _ = emit(.leftMouseUp, at: current?.location ?? .zero,
                 flags: current?.flags ?? [], proxy: proxy)
        dragging = false
        status = enabled ? "Hold \(key.displayName) to drag; release to drop." : "Drag helper is off."
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType,
                        event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stop()
            status = "macOS interrupted the listener. Drag released; enable again when ready."
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != marker else {
            return Unmanaged.passUnretained(event)
        }
        let code = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp, swallowedKeys.remove(code) != nil { return nil }

        if type == .keyDown && code == 53 { // Escape, including the emergency chord.
            let emergency: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
            if event.flags.intersection(emergency) == emergency {
                releaseDrag(proxy: proxy, event: event)
                // Disable after returning from the callback.
                DispatchQueue.main.async { [weak self] in self?.stop() }
                return nil
            }
            if held {
                releaseDrag(proxy: proxy, event: event)
                swallowedKeys.insert(code)
                // Keep the activation key latched until its key-up; repeats cannot restart.
                return nil
            }
        }

        let modifierEvent = type == .flagsChanged && key.modifierFlag != nil && code == key.code
        let modifierDown = modifierEvent && CGEventSource.keyState(.combinedSessionState, key: code)
        let activationDown = (type == .keyDown && code == key.code) || modifierDown
        let activationUp = (type == .keyUp && code == key.code) || (modifierEvent && !modifierDown)

        if type == .flagsChanged && held && !activationUp {
            let required = CGEventFlags(rawValue: key.modifiers)
            if !event.flags.isSuperset(of: required) {
                releaseDrag(proxy: proxy, event: event)
            }
        }
        if activationDown {
            if held { return nil }
            // Leave modified shortcuts and an existing physical drag alone.
            guard key.matches(code: code, flags: event.flags),
                  event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                  !CGEventSource.buttonState(.combinedSessionState, button: .left),
                  !CGEventSource.buttonState(.combinedSessionState, button: .right),
                  !CGEventSource.buttonState(.combinedSessionState, button: .center) else {
                return Unmanaged.passUnretained(event)
            }
            held = true
            let flags = key.mouseFlags(event.flags)
            dragging = emit(.leftMouseDown, at: event.location, flags: flags, proxy: proxy)
            if dragging {
                status = "Dragging — release \(key.displayName) to drop, or press Escape."
                let timer = Timer(timeInterval: 60, repeats: false) { [weak self] _ in
                    self?.releaseDrag()
                    self?.status = "Drag released after 60 seconds. Release the key before dragging again."
                }
                deadline = timer
                RunLoop.main.add(timer, forMode: .common)
            } else {
                status = "Could not create a mouse event."
            }
            return nil
        }
        if activationUp && held {
            releaseDrag(proxy: proxy, event: event)
            held = false
            return nil
        }
        if type == .leftMouseUp && swallowLeftUp {
            swallowLeftUp = false
            return nil
        }
        if dragging {
            switch type {
            case .mouseMoved, .leftMouseDragged:
                event.type = .leftMouseDragged
                event.flags = key.mouseFlags(event.flags)
                event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
                event.setIntegerValueField(.mouseEventClickState, value: 1)
            case .leftMouseDown:
                swallowLeftUp = true
                return nil
            case .leftMouseUp:
                return nil
            case .rightMouseDown, .otherMouseDown:
                releaseDrag(proxy: proxy, event: event)
            default:
                break
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
