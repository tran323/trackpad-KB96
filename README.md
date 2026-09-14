# KB96 Control — small macOS version

A menu-bar utility for using a JOMAA KB96 trackpad with a Mac mini. macOS 13 or later; Apple Silicon or Intel. No external packages, firmware changes, or system extensions.

This is a deliberately small adaptation of [the original requirements](KB96_Control_macOS_Requirements.md). The release build and app signature have been verified on macOS; hardware behavior still requires testing.

## What is implemented

- Record a key or shortcut to press the left mouse button, move the trackpad to drag, and release to drop. F6 is the default; existing F6–F9 selections migrate automatically.
- Customize primary/secondary clicks (including taps that produce those clicks), scroll speed and scroll direction. These optional mappings apply to all pointing devices while the helper is enabled.
- Escape releases a drag. Control + Option + Command + Escape releases and disables the helper.
- Menu-bar enable/disable, settings window, saved activation key. The helper enables at launch by default once Accessibility access is granted, and disables on sleep or session deactivation.
- Ordinary pointer motion is converted to left-button drag motion while the key is held. Existing macOS clicking, scrolling and tracking speed remain in use.
- A read-only HID inspector: device identity, HID elements, raw report bytes, decoded scalar values, connect/disconnect updates and a diagnostic text export. JOMAA / KB96 name matches are suggested; no vendor/product IDs are guessed.

The drag helper uses system pointer events, so it applies to **all pointing devices while the activation key is held**. It requires the KB96 to already move the pointer in macOS. It cannot make an unrecognized USB/Bluetooth device work. It does not seize the trackpad or decode a proprietary multitouch protocol. Separate finger-count gestures, tap-and-hold recognition, pointer-speed overrides and profiles need actual device reports before implementation.

## Build on your Mac

1. Copy this whole folder to the Mac mini.
2. Install Apple's Xcode Command Line Tools if needed: `xcode-select --install`.
3. In Terminal, change to this folder, then run:

   ```bash
   bash scripts/build-macos.sh
   ```

4. Move `dist/KB96 Control.app` to `/Applications` and open it. The script builds for the Mac's current architecture and applies an ad-hoc signature for local use. It does not produce a notarized distribution build.
5. If access is missing, click **Grant Accessibility…** and enable **KB96 Control** in System Settings → Privacy & Security → Accessibility. The app detects the grant and completes its pending startup automatically. When access is already granted, it shows **Accessibility granted**. For HID capture, also grant Input Monitoring when requested. Quit and reopen if macOS still does not recognize a permission change.

Use the bundled `.app` rather than `swift run` so permissions belong to a stable app path. Rebuilding an ad-hoc signed app can require removing and re-adding it in Privacy & Security settings.

For builds signed with an installed certificate, set `KB96_SIGNING_IDENTITY` to your code-signing identity when running the build script. Use the same identity for subsequent updates to maintain signing continuity. The default remains ad-hoc signing; switching identities can also require granting permission again.

## Launch at login

After moving the app to `/Applications`, open it once. It automatically registers to open when you sign in to your Mac. In the **General** tab, use **Launch at login** to turn this off or back on. If macOS requires approval, use **Open Login Items Settings…** and allow KB96 Control. Changes made in System Settings are reflected when you return to the app.

**Enable drag helper at launch** is on by default in General and is saved separately from **Launch at login**. Startup checks Accessibility silently and enables the helper if allowed. If access is missing, it waits for permission without repeatedly opening a permission prompt. **Release and Disable**, sleep, session deactivation and listener interruptions cancel a pending start and keep the helper off until manually enabled or the app is relaunched. Turn off **Enable drag helper at launch** to keep it off on future launches.

## Try dragging

1. Click the **Hold to drag** input, press and release your chosen key or combination, and enable the helper if it was off. Recording pauses the helper and restores its previous state afterward; Escape or leaving the window cancels recording.
2. Put the pointer on a window title bar or a file in Finder.
3. Hold the recorded key (F6 by default), move one finger, then release it.
4. For a screenshot area, press Command + Shift + 4, release those keys, position the crosshair, then hold F6, move, and release.

Letters, digits, Space, Tab, arrows, function keys, individual Shift/Control/Option/Command/Fn keys, and combinations such as Control + Space can be recorded. Escape stays reserved for release/cancel; Caps Lock, power and media-only events are not hold-to-drag inputs. If F6 performs a media/system action, use **Fn + F6**, or configure the keyboard to use standard function keys.

The exact shortcut is consumed across apps while the helper is enabled. Assigning a plain letter or Space prevents normal typing of that key until the helper is disabled. Other modifier combinations pass through unless the activation key is already held for dragging. Activation modifiers are removed from generated mouse events. Releasing a required modifier ends a drag; release the main key before starting another. Existing physical button drags are left alone. Avoid tapping/clicking the trackpad during a key-controlled drag.

Escape releases the button; the activation key must be released before another drag begins. The emergency chord, menu's **Release and Disable**, sleep, normal quit and an interrupted event tap also release the button. A 60-second limit handles a missed key-up. After a forced process kill or crash, a physical click/release may be needed to clear a synthetic drag; this prototype has no separate recovery process.

## Customize gesture outputs

In **Gestures**, turn on **Customize clicks and scrolling** while the helper is enabled. Choose Default, Left click, Right click, Middle click or Disabled for primary/secondary input. Adjust scroll speed (0.25×–3×), or reverse either scroll axis relative to the current macOS direction. Settings persist across launches. Click mappings remain paired through button release even if you change settings mid-drag.

These are mappings of the events macOS receives, not finger-count recognizers. One-finger taps can be customized when the device sends primary clicks; two-finger taps when it sends secondary clicks. Physical clicks and other mice receive the same mappings. **Control + Option + Command + Escape** releases and disables the helper if a mapping makes clicking inconvenient.

For separate one-/two-finger rules, double-tap-and-drag, or holds, live HID captures are still required. A device advertising Contact ID, Tip Switch or Contact Count does not establish which reports actually arrive during a gesture.

## Capture the trackpad for the next iteration

1. Open **HID Inspector**, click **Scan Devices**, and select the Jomaa interface. If the name is generic, unplug/reconnect the trackpad and compare the list. Multiple entries may belong to the same physical trackpad.
2. Enter a gesture label (for example **one-finger tap** or **two-finger tap**) and start capture. Repeat that gesture several times, then stop and export before recording the next gesture. Also capture one-finger hold-and-move, double-tap-and-drag, physical press/release, two-finger scroll, and any multi-finger gestures you want to customize. The label is included in the export.
3. Stop and export diagnostics. For a busy device, clear and export a separate short capture for each gesture. The log retains 500 lines, throttles busy streams, and shows the first 128 bytes of each report; truncation is marked.
4. Repeat for other trackpad interfaces if needed. Discovery does not open the listed devices. Only the selected interface is opened for capture and its input is logged. A selected keyboard interface can include keystroke codes, so avoid typing private text during capture.

Digitizer elements such as Contact ID, Tip Switch and Contact Count are labeled when present. Their presence in a descriptor alone does not establish that usable multitouch contacts are sent. Unknown/vendor-defined reports remain hex bytes. A silent capture may mean the wrong interface, missing Input Monitoring permission, or a report path macOS does not expose to this app.

Send back the build error (if any), macOS version, USB/Bluetooth connection type, which drag steps worked, and the exported capture for any failing gesture. Screenshot selection and Finder dragging are intended behaviors awaiting your Mac test.

## Source map

- `Sources/KB96Control/App.swift`: menu bar and SwiftUI settings/inspector.
- `Sources/KB96Control/DragController.swift`: event tap and drag lifecycle.
- `Sources/KB96Control/DragShortcut.swift` and `ShortcutRecorder.swift`: persisted shortcut matching and keyboard recording.
- `Sources/KB96Control/GestureSettings.swift`: click/scroll mappings and settings.
- `Sources/KB96Control/HIDInspector.swift`: nonexclusive HID access and diagnostics.
- `Sources/KB96Control/LoginItemController.swift`: launch-at-login registration and status.
- `scripts/build-macos.sh`: creates the local macOS app bundle.
- `Tests/KB96ControlTests/InputTests.swift`: shortcut migration/matching and pointer mapping checks (`swift test`).

HID discovery uses Apple's [independent-device manager option](https://github.com/apple-oss-distributions/IOKitUser/blob/main/hid.subproj/IOHIDManager.h) so opening the manager does not open every discovered device.

API references: [Apple CGEvent documentation](https://developer.apple.com/documentation/coregraphics/cgevent) and [IOHIDDeviceRegisterInputReportCallback](https://developer.apple.com/documentation/iokit/1588666-iohiddeviceregisterinputreportca).
