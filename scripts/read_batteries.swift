#!/usr/bin/env swift
// Reads ALL Battery Service (0x180F) characteristics (0x2A19) from a connected
// or in-range Keyball39 BLE device via CoreBluetooth — bypasses Apple's
// IOBluetooth filter that only surfaces the primary BAS.
//
// First run will prompt for Bluetooth permission. Grant it under
// System Settings > Privacy & Security > Bluetooth for the running terminal.
//
// Usage: swift read_batteries.swift

import CoreBluetooth
import Foundation

let DEVICE_NAME_PREFIX = "Keyball"
let BAS_SERVICE = CBUUID(string: "180F")
let BATTERY_LEVEL_CHAR = CBUUID(string: "2A19")
let LOG_PATH = "/tmp/battery_reader.log"

// Redirect stdout/stderr to a log file so this can be launched via `open`
// (which detaches stdio) and we can still see what happened.
let logFD = open(LOG_PATH, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
if logFD >= 0 {
    dup2(logFD, fileno(stdout))
    dup2(logFD, fileno(stderr))
    close(logFD)
    setvbuf(stdout, nil, _IONBF, 0)
}
print("BatteryReader started at \(Date())")

class BatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var target: CBPeripheral?
    var readings: [Int] = []
    var pendingReads = 0
    var totalBasInstances = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth on. Looking for already-connected Keyball...")
            let connected = central.retrieveConnectedPeripherals(withServices: [BAS_SERVICE])
            for p in connected {
                if let name = p.name, name.contains(DEVICE_NAME_PREFIX) {
                    print("  found already-connected: \(name)")
                    connectTo(p)
                    return
                }
            }
            print("  not in connected list — scanning for 15s...")
            central.scanForPeripherals(withServices: nil, options: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                if self.target == nil {
                    print("  no Keyball found via scan. Is it paired & in range?")
                    exit(1)
                }
            }
        case .unauthorized:
            print("ERROR: Bluetooth permission denied.")
            print("Grant under System Settings > Privacy & Security > Bluetooth")
            print("(the running terminal app needs the toggle ON)")
            exit(2)
        case .poweredOff:
            print("ERROR: Bluetooth is OFF on this Mac")
            exit(1)
        case .unsupported:
            print("ERROR: this Mac doesn't support BLE")
            exit(1)
        case .resetting:
            print("BT resetting...")
        case .unknown:
            print("BT state unknown, waiting...")
        @unknown default:
            print("BT state \(central.state.rawValue)")
        }
    }

    func connectTo(_ p: CBPeripheral) {
        target = p
        p.delegate = self
        central.connect(p, options: nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard target == nil,
              let name = peripheral.name,
              name.contains(DEVICE_NAME_PREFIX) else { return }
        print("  scan found: \(name) rssi=\(RSSI)")
        central.stopScan()
        connectTo(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("connected. discovering services...")
        peripheral.discoverServices([BAS_SERVICE])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        print("ERROR: failed to connect: \(error?.localizedDescription ?? "unknown")")
        exit(1)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("ERROR: service discovery: \(error)")
            exit(1)
        }
        let basServices = peripheral.services?.filter { $0.uuid == BAS_SERVICE } ?? []
        totalBasInstances = basServices.count
        print("found \(basServices.count) Battery Service instance(s)")
        if basServices.isEmpty {
            print("  (none — check that CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y on the keyboard)")
            exit(0)
        }
        for s in basServices {
            peripheral.discoverCharacteristics([BATTERY_LEVEL_CHAR], for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil else {
            print("ERROR: char discovery: \(error!)")
            return
        }
        for c in service.characteristics ?? [] where c.uuid == BATTERY_LEVEL_CHAR {
            pendingReads += 1
            peripheral.readValue(for: c)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let data = characteristic.value, let byte = data.first {
            readings.append(Int(byte))
        } else if let error = error {
            print("  read error: \(error)")
        }
        pendingReads -= 1
        if pendingReads == 0 {
            print("")
            print("=== BATTERY LEVELS ===")
            for (i, level) in readings.enumerated() {
                let label = readings.count == 2
                    ? (i == 0 ? "CENTRAL (right):  " : "PERIPHERAL (left): ")
                    : "BAS[\(i)]: "
                print("\(label)\(level)%")
            }
            central.cancelPeripheralConnection(peripheral)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                exit(0)
            }
        }
    }
}

let reader = BatteryReader()
DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
    print("ERROR: 30s timeout")
    exit(1)
}
RunLoop.main.run()
