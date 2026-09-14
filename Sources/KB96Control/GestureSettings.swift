import AppKit
import Combine
import SwiftUI

enum ClickAction: String, Codable, CaseIterable, Identifiable {
    case unchanged = "Default", left = "Left click", right = "Right click", middle = "Middle click", ignore = "Disabled"
    var id: String { rawValue }

    func button(original: Int) -> Int? {
        switch self {
        case .unchanged: return original
        case .left: return 0
        case .right: return 1
        case .middle: return 2
        case .ignore: return nil
        }
    }
}

final class GestureSettings: ObservableObject {
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "gestureOutputsEnabled") } }
    @Published var primary: ClickAction { didSet { defaults.set(primary.rawValue, forKey: "primaryClickAction") } }
    @Published var secondary: ClickAction { didSet { defaults.set(secondary.rawValue, forKey: "secondaryClickAction") } }
    @Published var scrollSpeed: Double { didSet { defaults.set(scrollSpeed, forKey: "gestureScrollSpeed") } }
    @Published var reverseVertical: Bool { didSet { defaults.set(reverseVertical, forKey: "gestureReverseVertical") } }
    @Published var reverseHorizontal: Bool { didSet { defaults.set(reverseHorizontal, forKey: "gestureReverseHorizontal") } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "gestureOutputsEnabled")
        primary = ClickAction(rawValue: defaults.string(forKey: "primaryClickAction") ?? "") ?? .unchanged
        secondary = ClickAction(rawValue: defaults.string(forKey: "secondaryClickAction") ?? "") ?? .unchanged
        let savedSpeed = defaults.object(forKey: "gestureScrollSpeed") as? Double ?? 1
        scrollSpeed = savedSpeed.isFinite ? min(max(savedSpeed, 0.25), 3) : 1
        reverseVertical = defaults.bool(forKey: "gestureReverseVertical")
        reverseHorizontal = defaults.bool(forKey: "gestureReverseHorizontal")
    }
}

/// Pair each physical down with its up, even if settings change while held.
struct PointerRemapper {
    private struct Press {
        let target: Int?
        var location: CGPoint
    }
    private var presses: [Int: Press] = [:]

    mutating func handle(_ event: CGEvent, settings: GestureSettings) -> CGEvent? {
        if event.type == .scrollWheel {
            guard settings.enabled else { return event }
            Self.scaleScroll(event, axis: 1, factor: settings.scrollSpeed * (settings.reverseVertical ? -1 : 1))
            Self.scaleScroll(event, axis: 2, factor: settings.scrollSpeed * (settings.reverseHorizontal ? -1 : 1))
            return event
        }
        let original: Int
        let phase: Int // 0 = down, 1 = drag, 2 = up
        switch event.type {
        case .leftMouseDown: original = 0; phase = 0
        case .rightMouseDown: original = 1; phase = 0
        case .leftMouseDragged: original = 0; phase = 1
        case .rightMouseDragged: original = 1; phase = 1
        case .leftMouseUp: original = 0; phase = 2
        case .rightMouseUp: original = 1; phase = 2
        case .otherMouseDown: original = max(2, Int(event.getIntegerValueField(.mouseEventButtonNumber))); phase = 0
        case .otherMouseDragged: original = max(2, Int(event.getIntegerValueField(.mouseEventButtonNumber))); phase = 1
        case .otherMouseUp: original = max(2, Int(event.getIntegerValueField(.mouseEventButtonNumber))); phase = 2
        default: return event
        }
        if phase == 0 {
            let action = settings.enabled && original < 2 ? (original == 0 ? settings.primary : settings.secondary) : .unchanged
            // Do not inject a second down for a button already held by another mapping.
            let target = action.button(original: original)
            let occupied = target.map { target in presses.contains { $0.key != original && $0.value.target == target } } ?? false
            presses[original] = Press(target: occupied ? nil : target, location: event.location)
        }
        guard var press = presses[original] else { return event }
        press.location = event.location
        presses[original] = press
        if phase == 2 { presses.removeValue(forKey: original) }
        guard let target = press.target else { return nil }
        event.type = Self.eventType(button: target, phase: phase)
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(target))
        return event
    }

    /// The controller posts these releases before removing its event tap.
    mutating func releaseEvents() -> [CGEvent] {
        defer { presses.removeAll() }
        return presses.compactMap { original, press in
            guard let target = press.target, target != original,
                  let button = CGMouseButton(rawValue: UInt32(target)) else { return nil }
            return CGEvent(mouseEventSource: nil, mouseType: Self.eventType(button: target, phase: 2),
                           mouseCursorPosition: press.location, mouseButton: button)
        }
    }

    private static func eventType(button: Int, phase: Int) -> CGEventType {
        let types: [[CGEventType]] = [
            [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
            [.rightMouseDown, .rightMouseDragged, .rightMouseUp],
            [.otherMouseDown, .otherMouseDragged, .otherMouseUp]
        ]
        return types[min(button, 2)][phase]
    }

    private static func scaleScroll(_ event: CGEvent, axis: Int, factor: Double) {
        guard factor != 1 else { return }
        let integerFields: [CGEventField] = axis == 1
            ? [.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1]
            : [.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2]
        // Setting the line delta also rewrites point/fixed deltas. Snapshot all
        // representations first so the multiplier is applied exactly once.
        let values = integerFields.map { Double(event.getIntegerValueField($0)) * factor }
        let fixedField: CGEventField = axis == 1 ? .scrollWheelEventFixedPtDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis2
        let fixedValue = event.getDoubleValueField(fixedField) * factor
        for (field, value) in zip(integerFields, values) {
            event.setIntegerValueField(field, value: Int64(max(-Double(Int32.max), min(Double(Int32.max), value)).rounded()))
        }
        event.setDoubleValueField(fixedField, value: fixedValue)
    }
}

struct GestureSettingsView: View {
    @ObservedObject var settings: GestureSettings
    @ObservedObject var drag: DragController

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Text("Gesture clicks and scrolling").font(.title.bold())
            Toggle("Customize clicks and scrolling", isOn: $settings.enabled)
            if !drag.enabled {
                Text("Enable the drag helper to apply these settings.").foregroundStyle(.secondary)
            }
            Group {
                Picker("Primary click / one-finger tap*", selection: $settings.primary) {
                    ForEach(ClickAction.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Secondary click / two-finger tap*", selection: $settings.secondary) {
                    ForEach(ClickAction.allCases) { Text($0.rawValue).tag($0) }
                }
                HStack {
                    Text("Scroll speed")
                    Slider(value: $settings.scrollSpeed, in: 0.25...3, step: 0.25)
                    Text(String(format: "%.2f×", settings.scrollSpeed)).monospacedDigit().frame(width: 60)
                }
                Toggle("Reverse vertical scrolling", isOn: $settings.reverseVertical)
                Toggle("Reverse horizontal scrolling", isOn: $settings.reverseHorizontal)
            }.disabled(!settings.enabled)
            Text("* Applies when your trackpad already turns these taps into primary/secondary clicks. Physical clicks and other mice are affected too; finger counts cannot be distinguished here.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("More finger gestures").font(.headline)
            Text("For one-finger hold, double-tap-and-drag, or separate multi-finger actions, capture each gesture in HID Inspector and export its diagnostics. Contact fields in the device descriptor alone do not prove that usable finger input is available.")
                .foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
        }
    }
}
