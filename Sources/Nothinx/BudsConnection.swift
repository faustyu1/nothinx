import Foundation
import IOBluetooth
import NothinxKit
import os

private let log = Logger(subsystem: "dev.nothinx.app", category: "rfcomm")

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

/// Owns the RFCOMM control channel to the earbuds. All callbacks arrive on the main run loop.
@MainActor
final class BudsConnection: NSObject {
    enum Status: Equatable {
        case noDevice
        case disconnected
        case connecting
        case connected
    }

    var onStatus: ((Status) -> Void)?
    var onFrame: ((Frame) -> Void)?

    private(set) var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var decoder = FrameDecoder()
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?
    private var retryTask: Task<Void, Never>?

    private static let namePrefixes = ["CMF Buds", "Nothing Ear", "Ear ("]

    var deviceName: String? { device?.name }

    func start() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        device = Self.findPairedBuds()
        if let device, device.isConnected() {
            openChannel(device)
        } else {
            onStatus?(device == nil ? .noDevice : .disconnected)
        }
    }

    /// Brings the Bluetooth link up; the connect notification then opens the control channel.
    func connect() {
        if device == nil { device = Self.findPairedBuds() }
        guard let device else { onStatus?(.noDevice); return }
        if device.isConnected() {
            openChannel(device)
        } else {
            onStatus?(.connecting)
            device.openConnection(self)
        }
    }

    func reconnect() {
        closeChannel()
        connect()
    }

    /// The buds silently drop requests that arrive back to back, so writes go out one at a time.
    private var outbox: [[UInt8]] = []
    private var drainTask: Task<Void, Never>?
    private static let sendGap: Duration = .milliseconds(150)

    func send(_ bytes: [UInt8]) {
        outbox.append(bytes)
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in
            while let self, !self.outbox.isEmpty {
                self.write(self.outbox.removeFirst())
                try? await Task.sleep(for: Self.sendGap)
            }
            self?.drainTask = nil
        }
    }

    private func write(_ bytes: [UInt8]) {
        guard let channel, channel.isOpen() else {
            log.notice("TX dropped, channel closed: \(hex(bytes), privacy: .public)")
            return
        }
        log.notice("TX \(hex(bytes), privacy: .public)")
        var data = bytes
        channel.writeAsync(&data, length: UInt16(data.count), refcon: nil)
    }

    private static func findPairedBuds() -> IOBluetoothDevice? {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let buds = paired.filter { device in
            namePrefixes.contains { device.name?.hasPrefix($0) == true }
        }
        return buds.first(where: { $0.isConnected() }) ?? buds.first
    }

    private static var serviceUUID: IOBluetoothSDPUUID {
        IOBluetoothSDPUUID(bytes: NothingProtocol.serviceUUID, length: 16)
    }

    private func rfcommChannelID(of device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
        let uuid = Self.serviceUUID
        for case let record as IOBluetoothSDPServiceRecord in device.services ?? [] where record.matchesUUIDArray([uuid]) {
            var id: BluetoothRFCOMMChannelID = 0
            if record.getRFCOMMChannelID(&id) == kIOReturnSuccess { return id }
        }
        return nil
    }

    private func openChannel(_ device: IOBluetoothDevice) {
        guard channel == nil else { return }
        self.device = device
        onStatus?(.connecting)
        disconnectNotification?.unregister()
        disconnectNotification = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))

        guard let id = rfcommChannelID(of: device) else {
            // Service records not cached yet; ask the buds and retry when the query finishes.
            device.performSDPQuery(self, uuids: [Self.serviceUUID])
            return
        }
        var newChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&newChannel, withChannelID: id, delegate: self)
        if result == kIOReturnSuccess {
            channel = newChannel
        } else {
            scheduleRetry()
        }
    }

    private func closeChannel() {
        outbox.removeAll()
        retryTask?.cancel()
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
        decoder = FrameDecoder()
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, let device = self.device, device.isConnected() else { return }
            self.channel = nil
            self.openChannel(device)
        }
    }

    // MARK: Notifications
    // IOBluetooth delivers these on its own threads, so each one hops to the main actor.

    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let device = UncheckedBox(device)
        onMain { [weak self] in
            guard Self.namePrefixes.contains(where: { device.value.name?.hasPrefix($0) == true }) else { return }
            self?.openChannel(device.value)
        }
    }

    @objc nonisolated private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onMain { [weak self] in
            self?.closeChannel()
            self?.onStatus?(.disconnected)
        }
    }

    // MARK: SDP / connection callbacks (informal protocols)

    @objc nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        let device = UncheckedBox(device)
        onMain { [weak self] in
            guard let self, self.channel == nil, device.value.isConnected() else { return }
            if self.rfcommChannelID(of: device.value) != nil {
                self.openChannel(device.value)
            } else {
                self.scheduleRetry()
            }
        }
    }

    @objc nonisolated func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        guard status != kIOReturnSuccess else { return }
        onMain { [weak self] in self?.onStatus?(.disconnected) }
    }
}

extension BudsConnection: IOBluetoothRFCOMMChannelDelegate {
    nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        onMain { [weak self] in
            guard let self else { return }
            if error == kIOReturnSuccess {
                self.onStatus?(.connected)
            } else {
                self.channel = nil
                self.scheduleRetry()
            }
        }
    }

    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        onMain { [weak self] in
            guard let self else { return }
            log.notice("RX \(hex(bytes), privacy: .public)")
            for frame in self.decoder.feed(bytes) { self.onFrame?(frame) }
        }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        let closedID = ObjectIdentifier(rfcommChannel)
        onMain { [weak self] in
            guard let self, let current = self.channel, ObjectIdentifier(current) == closedID else { return }
            self.channel = nil
            if self.device?.isConnected() == true {
                self.scheduleRetry()
            } else {
                self.onStatus?(.disconnected)
            }
        }
    }
}

/// Carries IOBluetooth objects (not Sendable) across the hop to the main actor.
private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

private func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(work)
    } else {
        DispatchQueue.main.async(execute: work)
    }
}
