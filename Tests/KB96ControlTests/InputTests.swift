import XCTest
import AppKit
@testable import KB96Control

final class InputTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "KB96ControlTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testExistingFunctionKeySelectionMigrates() {
        defaults.set("F8", forKey: "dragKey")
        XCTAssertEqual(DragShortcut.load(from: defaults).code, 100)
        let shortcut = DragShortcut(code: 49, modifiers: CGEventFlags.maskControl.rawValue, name: "Space")
        defaults.set(try! JSONEncoder().encode(shortcut), forKey: "dragShortcut")
        XCTAssertEqual(DragShortcut.load(from: defaults), shortcut)
    }

    func testExactShortcutMatchingAndMouseModifiers() {
        let shortcut = DragShortcut(code: 0, modifiers: CGEventFlags.maskCommand.rawValue, name: "A")
        XCTAssertTrue(shortcut.matches(code: 0, flags: [.maskCommand, .maskSecondaryFn, .maskAlphaShift]))
        XCTAssertFalse(shortcut.matches(code: 0, flags: [.maskCommand, .maskShift]))
        XCTAssertFalse(shortcut.matches(code: 1, flags: .maskCommand))
        XCTAssertEqual(shortcut.mouseFlags([.maskCommand, .maskShift, .maskSecondaryFn]), .maskShift)
        let modifier = DragShortcut(code: 58, modifiers: 0, name: "Left Option")
        XCTAssertTrue(modifier.matches(code: 58, flags: .maskAlternate))
        XCTAssertEqual(modifier.mouseFlags(.maskAlternate), [])
    }

    func testReservedAndCorruptedShortcutsAreRejected() {
        XCTAssertFalse(DragShortcut(code: 53, modifiers: 0, name: "Escape").isValid)
        XCTAssertFalse(DragShortcut(code: 57, modifiers: 0, name: "Caps Lock").isValid)
        defaults.set(Data("invalid".utf8), forKey: "dragShortcut")
        XCTAssertEqual(DragShortcut.load(from: defaults), .defaultShortcut)
    }

    func testRemappedDragAndUpKeepOriginalMappingAfterSettingsChange() {
        let settings = GestureSettings(defaults: defaults)
        settings.enabled = true
        settings.primary = .right
        var remapper = PointerRemapper()
        XCTAssertEqual(remapper.handle(mouse(.leftMouseDown), settings: settings)?.type, .rightMouseDown)
        settings.enabled = false
        settings.primary = .middle
        XCTAssertEqual(remapper.handle(mouse(.leftMouseDragged), settings: settings)?.type, .rightMouseDragged)
        XCTAssertEqual(remapper.handle(mouse(.leftMouseUp), settings: settings)?.type, .rightMouseUp)
        XCTAssertTrue(remapper.releaseEvents().isEmpty)
    }

    func testIgnoredClickSuppressesWholeSequence() {
        let settings = GestureSettings(defaults: defaults)
        settings.enabled = true
        settings.secondary = .ignore
        var remapper = PointerRemapper()
        XCTAssertNil(remapper.handle(mouse(.rightMouseDown), settings: settings))
        settings.secondary = .left
        XCTAssertNil(remapper.handle(mouse(.rightMouseDragged), settings: settings))
        XCTAssertNil(remapper.handle(mouse(.rightMouseUp), settings: settings))
    }

    func testStoppingReleasesRemappedButtonOnce() {
        let settings = GestureSettings(defaults: defaults)
        settings.enabled = true
        settings.primary = .middle
        var remapper = PointerRemapper()
        _ = remapper.handle(mouse(.leftMouseDown), settings: settings)
        let releases = remapper.releaseEvents()
        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases.first?.type, .otherMouseUp)
        XCTAssertEqual(releases.first?.getIntegerValueField(.mouseEventButtonNumber), 2)
        XCTAssertTrue(remapper.releaseEvents().isEmpty)
    }

    func testTwoInputsCannotReleaseEachOthersMappedButton() {
        let settings = GestureSettings(defaults: defaults)
        settings.enabled = true
        settings.secondary = .left
        var remapper = PointerRemapper()
        XCTAssertNotNil(remapper.handle(mouse(.leftMouseDown), settings: settings))
        XCTAssertNil(remapper.handle(mouse(.rightMouseDown), settings: settings))
        XCTAssertNil(remapper.handle(mouse(.rightMouseUp), settings: settings))
        XCTAssertEqual(remapper.handle(mouse(.leftMouseUp), settings: settings)?.type, .leftMouseUp)
    }

    func testScrollSpeedAndDirectionUpdateAllRepresentations() {
        let settings = GestureSettings(defaults: defaults)
        settings.enabled = true
        settings.scrollSpeed = 2
        settings.reverseVertical = true
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 4, wheel2: 3, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 4)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 4)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 4)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 3)
        var remapper = PointerRemapper()
        let result = remapper.handle(event, settings: settings)!
        XCTAssertEqual(result.getIntegerValueField(.scrollWheelEventDeltaAxis1), -8)
        XCTAssertEqual(result.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -8)
        XCTAssertEqual(result.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), -8)
        XCTAssertEqual(result.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), 6)
    }

    private func mouse(_ type: CGEventType) -> CGEvent {
        let button: CGMouseButton = [.rightMouseDown, .rightMouseDragged, .rightMouseUp].contains(type) ? .right : .left
        return CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: 100, y: 200), mouseButton: button)!
    }
}
