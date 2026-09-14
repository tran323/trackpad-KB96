import AppKit
import Combine
import IOKit
import IOKit.hid

struct HIDDeviceInfo: Identifiable {
    let id: UInt64
    let device: IOHIDDevice
    let name: String
    let manufacturer: String
    let vendor: Int
    let product: Int
    let page: Int
    let usage: Int
    let transport: String

    var likelyKB96: Bool {
        let text = (name + " " + manufacturer).lowercased()
        return text.contains("jomaa") || text.contains("kb96")
    }
    var label: String {
        String(format: "%@ — %04X:%04X · %02X/%02X · %@", name, vendor, product, page, usage, transport)
    }
    var details: String {
        "\(label)\nManufacturer: \(manufacturer)\nRegistry ID: \(id)\n"
    }

    init(_ device: IOHIDDevice) {
        self.device = device
        func number(_ key: String) -> Int {
            (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
        }
        func string(_ key: String) -> String {
            IOHIDDeviceGetProperty(device, key as CFString) as? String ?? "Unknown"
        }
        var registryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryID)
        id = registryID
        name = string(kIOHIDProductKey)
        manufacturer = string(kIOHIDManufacturerKey)
        vendor = number(kIOHIDVendorIDKey)
        product = number(kIOHIDProductIDKey)
        page = number(kIOHIDPrimaryUsagePageKey)
        usage = number(kIOHIDPrimaryUsageKey)
        transport = string(kIOHIDTransportKey)
    }
}

final class HIDInspector: ObservableObject {
    @Published private(set) var devices: [HIDDeviceInfo] = []
    @Published private(set) var capturing = false
    @Published private(set) var status = "Scan devices to find your trackpad."
    @Published private(set) var log = ""
    @Published private(set) var descriptor = ""
    @Published var gestureLabel = ""
    @Published var selectedID: UInt64? { didSet { if oldValue != selectedID { stopCapture() } } }

    private var manager: IOHIDManager?
    private var active: IOHIDDevice?
    // Keep one stable buffer alive until callbacks are unregistered and unscheduled.
    private let capacity = 65_536
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65_536)
    private var rows: [String] = []
    private var pending: [String] = []
    private var omitted = 0
    private var timer: Timer?
    private var captureIdentity = ""
    private var reportCount = 0
    private var valueCount = 0

    var selected: HIDDeviceInfo? { devices.first { $0.id == selectedID } }

    func scan() {
        if manager == nil {
            // kIOHIDManagerOptionIndependentDevices (IOHIDManager.h): discovery
            // must not open or schedule every keyboard/mouse on the computer.
            let independentDevices: IOOptionBits = 0x8
            let newManager = IOHIDManagerCreate(kCFAllocatorDefault, independentDevices)
            manager = newManager
            IOHIDManagerSetDeviceMatching(newManager, nil)
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(newManager, { context, _, _, _ in
                guard let context else { return }
                Unmanaged<HIDInspector>.fromOpaque(context).takeUnretainedValue().refresh()
            }, context)
            IOHIDManagerRegisterDeviceRemovalCallback(newManager, { context, _, _, device in
                guard let context else { return }
                let owner = Unmanaged<HIDInspector>.fromOpaque(context).takeUnretainedValue()
                if let active = owner.active, CFEqual(active, device) {
                    owner.stopCapture()
                    owner.status = "Selected device disconnected. Capture stopped."
                }
                DispatchQueue.main.async { [weak owner] in owner?.refresh() }
            }, context)
            IOHIDManagerScheduleWithRunLoop(newManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            let result = IOHIDManagerOpen(newManager, IOOptionBits(kIOHIDOptionsTypeNone))
            if result != kIOReturnSuccess {
                shutdown()
                status = String(format: "HID access failed (0x%08X). Allow Input Monitoring and reopen the app.", UInt32(bitPattern: result))
                return
            }
        }
        refresh()
        status = "Found \(devices.count) HID interfaces. Select the trackpad interface to inspect."
    }

    private func refresh() {
        guard let manager else { return }
        let found = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        devices = found.map(HIDDeviceInfo.init).sorted {
            if $0.likelyKB96 != $1.likelyKB96 { return $0.likelyKB96 }
            return $0.label == $1.label ? $0.id < $1.id : $0.label < $1.label
        }
        if let selectedID, !devices.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
        if selectedID == nil { selectedID = devices.first(where: \.likelyKB96)?.id }
    }

    func startCapture() {
        stopCapture()
        guard let selected else { status = "Select the Jomaa interface first."; return }
        let device = selected.device
        let size = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 4096
        guard size > 0 && size <= capacity else {
            status = "Unsupported report size: \(size)."
            return
        }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            status = String(format: "Could not open this interface (0x%08X). Check Input Monitoring.", UInt32(bitPattern: result))
            return
        }
        clear()
        captureIdentity = selected.details + "Gesture tested: \(gestureLabel.isEmpty ? "Not labeled" : gestureLabel)\n"
        let elements = (IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]) ?? []
        descriptor = elements.map { element in
            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            return String(format: "report=%u cookie=%u page=%04X usage=%04X %@ range=%ld…%ld bits=%u relative=%@",
                          IOHIDElementGetReportID(element), IOHIDElementGetCookie(element), page, usage,
                          HIDInspector.usageName(page: page, usage: usage),
                          IOHIDElementGetLogicalMin(element), IOHIDElementGetLogicalMax(element),
                          IOHIDElementGetReportSize(element), IOHIDElementIsRelative(element) ? "yes" : "no")
        }.joined(separator: "\n")
        active = device
        capturing = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, size, { context, result, _, _, reportID, report, length in
            guard let context else { return }
            let owner = Unmanaged<HIDInspector>.fromOpaque(context).takeUnretainedValue()
            guard owner.capturing else { return }
            guard result == kIOReturnSuccess else {
                owner.append("Report error: \(result)")
                return
            }
            owner.reportCount += 1
            guard owner.pending.count < 200 else { owner.omitted += 1; return }
            let count = min(max(length, 0), 128)
            let bytes = UnsafeBufferPointer(start: report, count: count)
            let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            owner.append("RAW id=\(reportID) length=\(length): \(hex)\(length > count ? " … [truncated]" : "")")
        }, context)
        IOHIDDeviceRegisterInputValueCallback(device, { context, result, _, value in
            guard let context else { return }
            let owner = Unmanaged<HIDInspector>.fromOpaque(context).takeUnretainedValue()
            guard owner.capturing, result == kIOReturnSuccess else { return }
            owner.valueCount += 1
            guard owner.pending.count < 200 else { owner.omitted += 1; return }
            let element = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            // IOHIDValueGetIntegerValue is only meaningful for scalar elements.
            let length = IOHIDValueGetLength(value)
            let decoded = length <= MemoryLayout<CFIndex>.size ? String(IOHIDValueGetIntegerValue(value)) : "[\(length) bytes]"
            owner.append(String(format: "VALUE report=%u cookie=%u page=%04X usage=%04X %@ = %@",
                                IOHIDElementGetReportID(element), IOHIDElementGetCookie(element),
                                page, usage, HIDInspector.usageName(page: page, usage: usage), decoded))
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.flush() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        status = "Capturing \(selected.name). Normal device behavior stays active."
    }

    func stopCapture() {
        capturing = false
        if let active {
            IOHIDDeviceUnscheduleFromRunLoop(active, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceRegisterInputReportCallback(active, buffer, capacity, nil, nil)
            IOHIDDeviceRegisterInputValueCallback(active, nil, nil)
            IOHIDDeviceClose(active, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        active = nil
        timer?.invalidate()
        timer = nil
        flush()
        status = "Capture stopped."
    }

    func shutdown() {
        stopCapture()
        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    func clear() {
        pending.removeAll()
        rows.removeAll()
        omitted = 0
        reportCount = 0
        valueCount = 0
        log = ""
    }

    private func append(_ message: String) {
        guard pending.count < 200 else { omitted += 1; return }
        pending.append(String(format: "%.3f %@", ProcessInfo.processInfo.systemUptime, message))
    }

    private func flush() {
        guard !pending.isEmpty || omitted > 0 else { return }
        rows.append(contentsOf: pending)
        pending.removeAll(keepingCapacity: true)
        if omitted > 0 {
            rows.append("[\(omitted) entries omitted to keep the inspector responsive]")
            omitted = 0
        }
        if rows.count > 500 { rows.removeFirst(rows.count - 500) }
        log = rows.joined(separator: "\n")
    }

    func export() {
        flush()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "KB96-diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = """
        KB96 Control diagnostics — \(Date())
        OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Capture device:
        \(captureIdentity)
        Reports received: \(reportCount); values received: \(valueCount)

        Connected HID interfaces:
        \(devices.map(\.details).joined(separator: "\n"))

        Elements (descriptor, not proof that the firmware sends contacts):
        \(descriptor)

        Recent input (uptime timestamps; bounded to 500 lines):
        \(log)
        """
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            status = "Saved \(url.lastPathComponent)."
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    private static func usageName(page: UInt32, usage: UInt32) -> String {
        switch page {
        case 0x01:
            let names: [UInt32: String] = [0x30: "X", 0x31: "Y", 0x38: "Wheel"]
            return names[usage] ?? "Generic Desktop"
        case 0x09: return "Button \(usage)"
        case 0x07: return "Keyboard"
        case 0x0C: return usage == 0x238 ? "Horizontal pan" : "Consumer control"
        case 0x0D:
            let names: [UInt32: String] = [0x22: "Finger", 0x30: "Tip pressure", 0x32: "In range", 0x42: "Tip switch",
                    0x47: "Confidence", 0x48: "Width", 0x49: "Height", 0x51: "Contact ID",
                    0x54: "Contact count", 0x55: "Contact count maximum", 0x56: "Scan time"]
            return names[usage] ?? "Digitizer"
        default: return "Other/vendor-defined"
        }
    }

    deinit {
        shutdown()
        buffer.deallocate()
    }
}
