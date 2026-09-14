# KB96 Control for macOS — Requirements Specification

## 1. Project Goal

Build a macOS utility for the **JOMAA KB96 / 2BFOV-KB96** trackpad that can take control of the device, suppress its default macOS behavior, inspect its raw HID input, and replace the default behavior with a fully customizable gesture and pointer engine.

The main goal is to make the KB96 behave more like a configurable Mac trackpad, especially fixing unreliable dragging and screenshot-area selection.

---

## 2. Target Device

- Device: **JOMAA KB96**
- Identifier/model: **2BFOV-KB96**
- Platform: **macOS**
- Primary development language: **Swift**
- UI framework: **SwiftUI**
- Input frameworks to investigate/use:
  - IOKit / IOHID
  - CoreHID where available
  - CoreGraphics / CGEvent
  - HIDDriverKit only if required later

---

## 3. Core Architecture

Desired input flow:

```text
JOMAA KB96
    |
    | raw HID reports
    v
KB96Control
    |
    |-- Seize / exclusively open KB96
    |-- Read raw HID input
    |-- Parse fingers / buttons / movement
    |-- Run custom gesture recognizer
    |-- Generate replacement input events
    v
macOS
```

The application should attempt to take control of **only the KB96**, without affecting the user's keyboard, mouse, or other pointing devices.

---

## 4. Disable Default KB96 Behavior

The app should attempt to suppress the normal behavior macOS receives from the KB96 before custom behavior is enabled.

### Requirements

- Detect the KB96 by HID identity.
- Read and record:
  - Vendor ID
  - Product ID
  - Product name
  - Manufacturer
  - Usage Page
  - Usage ID
  - Transport
- Support opening the KB96 in exclusive / seized mode where macOS permits it.
- Investigate:
  - `kIOHIDOptionsTypeSeizeDevice`
  - CoreHID device seizure APIs where supported.
- Seizing must apply only to the KB96.
- Other input devices must continue to work.
- User must be able to release exclusive control immediately.
- If exclusive seizure is not possible from a normal macOS app, investigate DriverKit/HIDDriverKit as a later phase.

---

## 5. Raw HID Inspector

Before implementing gestures, build a diagnostic tool that shows exactly what the KB96 hardware and firmware send to macOS.

### Inspector must display

```text
Device identification

Vendor ID
Product ID
Product name
Manufacturer
Usage Page
Usage ID
Transport
Report IDs

Raw HID reports

Buttons
Pointer movement
Scroll input
Contact count
Finger/contact IDs
Finger X/Y coordinates
Touch state
Finger down
Finger up
Tip switch
Confidence
Pressure, if available
Width/height, if available
Any gesture-related values
Any keyboard/media events produced by the trackpad firmware
```

### Test cases

The user should test:

- Move one finger.
- Single tap.
- Double tap.
- Physical press.
- Press and hold.
- Press + move.
- Two-finger tap.
- Two-finger vertical scroll.
- Two-finger horizontal scroll.
- Pinch in/out.
- Three-finger swipe up.
- Three-finger swipe down.
- Three-finger swipe left.
- Three-finger swipe right.
- Three-finger drag.
- Four-finger gestures.
- Finger contact without movement.
- Finger release.

The inspector must make it easy to determine whether the KB96 exposes real multitouch contact information or only processed mouse/keyboard commands.

---

## 6. Hardware Capability Detection

The software must determine what can actually be customized based on the reports exposed by the KB96.

### Best case

If the trackpad exposes data similar to:

```text
contactCount: 3

Finger 1:
  id: 1
  x: 521
  y: 315
  touched: true

Finger 2:
  id: 2
  x: 603
  y: 330
  touched: true

Finger 3:
  id: 3
  x: 691
  y: 322
  touched: true
```

then the application can implement its own multitouch gesture recognizer.

### Limited case

If the KB96 exposes only data such as:

```text
Mouse move: +10, +3
Scroll: -5
Keyboard shortcut: Mission Control
```

then customization will be limited because the firmware has already converted gestures into higher-level commands.

### Hardware limitation rule

Software can only customize information that the hardware exposes.

Examples:

- If pressure data is not available, true Force Touch cannot be implemented.
- If finger positions are not available, custom pinch/rotation recognition may not be possible.
- If physical press generates no HID event, software cannot detect that press directly.

---

## 7. Custom Pointer Engine

When the KB96 is under custom control, implement pointer behavior in software.

### Required settings

- Pointer movement
- Tracking speed
- Pointer acceleration
- Optional linear pointer movement
- Optional macOS-like acceleration
- Sensitivity adjustment
- Dead-zone adjustment if needed
- Movement filtering if KB96 input is noisy

---

## 8. One-Finger Behavior

All behaviors should be configurable.

Default proposed mapping:

```text
Move
    -> Move pointer

Single tap
    -> Left click

Double tap
    -> Double click

Tap + hold + move
    -> Drag

Finger release while dragging
    -> Drop / left mouse up
```

Optional settings:

- Tap-to-click on/off
- Double-tap timeout
- Hold delay
- Drag threshold
- Drag lock
- Click sensitivity
- Ignore accidental taps

---

## 9. Dragging Engine

Fixing drag behavior is a primary requirement.

### Expected behavior

```text
finger down
    |
hold for configurable delay
    |
movement exceeds threshold
    |
generate leftMouseDown
    |
continue movement
    |
generate leftMouseDragged
    |
finger up
    |
generate leftMouseUp
```

### Dragging requirements

- Must work reliably in Finder.
- Must move files and folders.
- Must drag application windows.
- Must support selecting text.
- Must support dragging UI controls/sliders.
- Must work with:
  - `Command + Shift + 4`
  - macOS screenshot area selection.
- Drag delay must be configurable.
- Movement threshold must be configurable.
- Optional drag lock.
- Optional double-tap-and-drag mode.
- Optional modifier-key drag mode as fallback.

Possible drag modes:

```text
Tap + Hold
Double Tap + Drag
Control + Move
Physical Button + Move
Three Finger Drag
Custom
```

---

## 10. Two-Finger Behavior

Default proposed mappings:

```text
Two-finger vertical movement
    -> Vertical scroll

Two-finger horizontal movement
    -> Horizontal scroll

Two-finger tap
    -> Right click

Pinch in/out
    -> Zoom
```

Settings:

- Natural scrolling on/off
- Scroll speed
- Horizontal scroll speed
- Momentum scrolling
- Scroll acceleration
- Scroll dead zone
- Right-click mapping
- Pinch sensitivity
- Disable pinch if unsupported

---

## 11. Three-Finger Behavior

Default proposed mappings:

```text
Three-finger swipe up
    -> Mission Control

Three-finger swipe down
    -> App Exposé

Three-finger swipe left
    -> Previous desktop / space

Three-finger swipe right
    -> Next desktop / space

Three-finger tap
    -> Custom action
```

All mappings must be user configurable.

Possible actions:

- Mission Control
- App Exposé
- Show Desktop
- Previous Space
- Next Space
- Back
- Forward
- Launchpad
- Keyboard shortcut
- Run custom action
- Disable

---

## 12. Four-Finger Behavior

Support four-finger gestures if raw hardware reports allow it.

Possible mappings:

```text
Four-finger tap
    -> Launchpad

Four-finger swipe
    -> Configurable action
```

All actions must be optional and configurable.

---

## 13. Gesture Engine

If raw multitouch reports are available, implement a custom recognizer.

Recognizer should eventually support:

- Tap
- Double tap
- Hold
- Drag
- Swipe
- Scroll
- Pinch
- Rotation, if hardware exposes enough information
- Finger count
- Gesture direction
- Gesture velocity
- Gesture distance
- Gesture duration
- Accidental-touch rejection

Gesture thresholds should be configurable.

---

## 14. Generated macOS Events

The app should generate replacement macOS events as required.

Examples:

- `mouseMoved`
- `leftMouseDown`
- `leftMouseDragged`
- `leftMouseUp`
- `rightMouseDown`
- `rightMouseUp`
- scroll wheel events
- keyboard shortcut events

CoreGraphics / `CGEvent` should be used initially where appropriate.

The application may require macOS Accessibility permission to inject input events.

---

## 15. Per-App Profiles

Future configuration should support profiles.

Example:

```text
Default
Finder
Xcode
Safari
Chrome
Terminal
Custom App
```

Each profile may override:

- Gestures
- Drag behavior
- Scroll speed
- Pointer speed
- Shortcut mappings

Example:

```text
Safari:
Three-finger left  -> Back
Three-finger right -> Forward

Xcode:
Three-finger left  -> Previous editor
Three-finger right -> Next editor
```

---

## 16. SwiftUI Configuration App

Build a simple settings UI.

Example:

```text
KB96 Control
------------------------------------------------

Device
  JOMAA KB96
  Status: Connected
  Exclusive Control: ON

Pointer
  Tracking Speed        [ slider ]
  Acceleration          [ slider ]

One Finger
  Tap                    Left Click
  Double Tap             Double Click
  Tap + Hold             Drag

Two Fingers
  Tap                    Right Click
  Vertical Swipe         Scroll
  Horizontal Swipe       Horizontal Scroll
  Pinch                  Zoom

Three Fingers
  Swipe Up               Mission Control
  Swipe Down             App Exposé
  Swipe Left             Previous Desktop
  Swipe Right            Next Desktop

Four Fingers
  Tap                    Launchpad

Dragging
  Enable Drag Fix        [x]
  Drag Mode              Tap + Hold
  Hold Delay             150 ms
  Drag Threshold         [ slider ]
  Drag Lock              [ ]

Scrolling
  Natural Scrolling      [x]
  Scroll Speed           [ slider ]
  Momentum               [x]

Safety
  Emergency Release      Control + Option + Command + Escape
```

---

## 17. Menu Bar App

The utility should preferably run as a menu-bar app.

Suggested menu:

```text
KB96 Control
--------------------
KB96 Connected

Enable Custom Control
Release KB96

Profile:
  Default
  Finder
  Xcode

Open Settings
Open HID Inspector
Quit
```

---

## 18. Safety Requirements

Exclusive device control can make the trackpad temporarily unusable, so safety mechanisms are mandatory.

### Emergency release shortcut

Default:

```text
Control + Option + Command + Escape
```

Action:

- Immediately stop exclusive KB96 handling.
- Release/seize lock.
- Restore normal KB96 behavior.
- Stop injected drag state.
- Send `leftMouseUp` if a drag is currently active.

### Additional safety

- Always allow quitting with keyboard.
- If the app crashes, the KB96 must return to normal OS control automatically where possible.
- Store settings safely.
- Start with exclusive mode OFF.
- Require explicit user action before entering exclusive mode during early development.
- Show a clear status indicator when the KB96 is seized.

---

## 19. Permissions

Investigate macOS permissions required for:

- HID access
- Input monitoring
- Accessibility
- Event injection
- Driver/system extension, if later required

The application should explain clearly when a permission is missing.

---

## 20. DriverKit / HIDDriverKit

Do **not** start with a custom system driver.

Initial implementation should attempt:

```text
Swift app
    +
IOHID / CoreHID
    +
CGEvent
```

Only move to HIDDriverKit if:

- Normal application APIs cannot suppress default KB96 behavior.
- The device cannot be seized reliably.
- Raw reports are available only at a driver level.
- macOS keeps interpreting unwanted device reports before the application can process them.

Potential future architecture:

```text
KB96
  |
Raw HID
  |
HIDDriverKit system extension
  |
Custom gesture engine
  |
Virtual / generated macOS input
```

DriverKit should be treated as an advanced later phase because it introduces:

- System extensions
- Entitlements
- Code signing requirements
- More complicated installation
- More difficult debugging

---

## 21. Development Phases

### Phase 1 — Device Discovery

Build a small Swift tool that:

- Finds the KB96.
- Prints HID identity.
- Lists collections/elements.
- Displays usage pages and usages.
- Confirms device connection/disconnection.

### Phase 2 — Raw HID Inspector

Implement raw report logging.

Goal:

Determine whether the KB96 exposes:

- Finger contacts
- Finger count
- Coordinates
- Touch/release
- Buttons
- Pressure
- Scroll data
- Gesture data
- Keyboard shortcuts generated by firmware

### Phase 3 — Exclusive Mode Test

Implement:

```text
Seize KB96
Release KB96
```

Confirm:

- KB96 default behavior disappears while seized.
- Other mouse/keyboard devices continue working.
- Device returns to normal after release.
- Emergency shortcut works.

### Phase 4 — Basic Pointer

Reimplement:

- Pointer movement
- Left click
- Right click
- Basic scroll

At this stage the KB96 should remain usable even though its original behavior is suppressed.

### Phase 5 — Drag Fix

Implement reliable:

```text
Tap + Hold + Move
```

Test:

- Finder file drag
- Window drag
- Text selection
- Screenshot area selection
- Generic UI controls

### Phase 6 — Gesture Engine

Add:

- One-finger gestures
- Two-finger gestures
- Three-finger gestures
- Four-finger gestures
- Pinch
- Swipe
- Custom mappings

Only enable gestures supported by available raw input.

### Phase 7 — Configuration UI

Build SwiftUI settings for:

- Pointer
- Dragging
- Scrolling
- Gesture mapping
- Profiles
- Device state
- Diagnostics

### Phase 8 — Menu Bar Utility

Add:

- Start/stop control
- Profile selection
- Device connection state
- Quick release
- Launch at login

### Phase 9 — Per-App Profiles

Add application-specific gesture behavior.

### Phase 10 — Advanced Driver Investigation

Only if required, investigate:

- DriverKit
- HIDDriverKit
- System extension architecture
- Virtual HID output if necessary

---

## 22. Recommended Project Structure

```text
KB96Control/
|
|-- App/
|   |-- KB96ControlApp.swift
|   |-- MenuBarController.swift
|   `-- AppState.swift
|
|-- Device/
|   |-- KB96DeviceManager.swift
|   |-- HIDDeviceInfo.swift
|   |-- HIDElementParser.swift
|   `-- RawReportReader.swift
|
|-- Inspector/
|   |-- HIDInspectorView.swift
|   |-- HIDEventLog.swift
|   `-- ReportFormatter.swift
|
|-- InputEngine/
|   |-- PointerEngine.swift
|   |-- ClickEngine.swift
|   |-- DragEngine.swift
|   |-- ScrollEngine.swift
|   `-- EventInjector.swift
|
|-- Gestures/
|   |-- GestureEngine.swift
|   |-- TapRecognizer.swift
|   |-- HoldRecognizer.swift
|   |-- SwipeRecognizer.swift
|   |-- PinchRecognizer.swift
|   `-- GestureState.swift
|
|-- Profiles/
|   |-- Profile.swift
|   |-- ProfileManager.swift
|   `-- AppProfileMatcher.swift
|
|-- Settings/
|   |-- SettingsView.swift
|   |-- PointerSettingsView.swift
|   |-- GestureSettingsView.swift
|   |-- DragSettingsView.swift
|   `-- ScrollSettingsView.swift
|
`-- Safety/
    |-- EmergencyReleaseManager.swift
    `-- DeviceRecoveryManager.swift
```

---

## 23. Functional Acceptance Criteria

The first useful version is successful when all of the following work:

- KB96 is detected automatically.
- Raw HID information can be inspected.
- User can seize/release only the KB96.
- Default KB96 behavior can be suppressed while under custom control.
- Cursor movement still works.
- Left click works.
- Right click works.
- Scrolling works.
- Reliable custom dragging works.
- Finder files can be dragged.
- Windows can be dragged.
- `Command + Shift + 4` screenshot selection works.
- Emergency release restores normal behavior.
- User can change at least the main gesture mappings.
- Preferences persist across launches.

---

## 24. Non-Goals for Initial Version

Do not initially attempt to:

- Replicate Apple Force Touch.
- Replace the entire macOS input subsystem.
- Build a kernel extension.
- Build a DriverKit extension before testing regular HID APIs.
- Guarantee gestures that the KB96 hardware does not expose.
- Modify KB96 firmware.

---

## 25. Main Technical Risk

The biggest unknown is the quality of the KB96 raw HID reports.

The project has two possible outcomes.

### Outcome A — Full multitouch reports available

Possible result:

```text
~90% configurable Mac-trackpad-like experience
```

The app can implement most gestures itself.

### Outcome B — Firmware only sends processed actions

Possible result:

```text
Advanced mouse/gesture remapper
```

The app can still improve:

- Dragging
- Screenshot selection
- Clicking
- Scrolling
- Gesture shortcuts
- Per-app mappings

But cannot reconstruct raw multitouch information that the firmware does not expose.

---

## 26. First Implementation Target

The very first deliverable should be:

**KB96 Raw HID Inspector**

It should:

1. Detect the KB96.
2. Print all device information.
3. Enumerate its HID elements.
4. Log incoming reports.
5. Identify finger/contact data if present.
6. Identify whether physical press produces any event.
7. Identify what two-, three-, and four-finger gestures actually send.
8. Provide a simple Seize / Release test.
9. Include the emergency release shortcut.

Only after these results are known should the full custom gesture engine be implemented.
