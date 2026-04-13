//
//  BLEManager.swift
//  Music2
//
//  Created by grace keywork on 2/16/26.
//

import Foundation       // Basic Swift stuff - always needed for any Swift code
import CoreBluetooth    // Apple's Bluetooth Low Energy framework - lets us talk to BLE devices
import Combine          // Needed for @Published to work - allows UI to watch for changes



// This class handles ALL Bluetooth communication with the ESP32
// NSObject - required by Apple's older frameworks like CoreBluetooth
// ObservableObject - means the UI can watch this class and update when things change
// CBCentralManagerDelegate - means this class will handle BLE central events (scanning, connecting)
// CBPeripheralDelegate - means this class will handle peripheral events (receiving data from ESP32)
class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
   
    @Published var messageEventID = UUID()
    
    // We use lazy because CoreBluetooth expects the delegate to exist first
    // before the CBCentralManager is fully created
    lazy var centralManager: CBCentralManager = CBCentralManager(
        delegate: self,
        queue: DispatchQueue.main,
        options: [CBCentralManagerOptionShowPowerAlertKey: true]
    )
    
    // ? means "this might be nil (empty) if we haven't found the ESP32 yet"
    var connectedPeripheral: CBPeripheral?      // The ESP32 device once we find and connect to it
    var targetCharacteristic: CBCharacteristic? // The specific data channel inside the ESP32 we talk through
    
    // These UUIDs must match the ESP32 side exactly
    let serviceUUID = CBUUID(string: "62e80d9b-5a2c-4bae-b4a0-02627fc00e7b")
    let characteristicUUID = CBUUID(string: "d4aff33c-2366-47c1-8460-3cc0b19517e6")
    
    // @Published means "whenever this value changes, tell the UI to update automatically"
    @Published var isConnected = false           // true when connected to ESP32, false when not
    @Published var lastReceivedMessage = ""      // Stores the last message received from ESP32
    
    // This runs automatically when BLEManager() is created
    // It sets up the Bluetooth manager and starts listening for BLE events
    override init() {
        super.init()
        print("BLEManager init() called")
        _ = centralManager // triggers the lazy var to actually initialize
        print("centralManager state: \(centralManager.state.rawValue)")
    }
    
    // These functions are called automatically by CoreBluetooth at specific moments
    // We don't call them ourselves - Apple's framework calls them for us
    
    // CALLED AUTOMATICALLY when Bluetooth state changes (on/off/unavailable/etc)
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("didUpdateState fired")
        print("Bluetooth state raw:", central.state.rawValue)
        
        // Check if Bluetooth is powered on and ready to use
        if central.state == .poweredOn {
            print("Bluetooth powered on - scanning for Music2 ESP32")
            
            // Start scanning for any device advertising our specific service UUID
            // Only devices with this exact service UUID will respond
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        } else {
            print("Bluetooth not ready:", central.state.rawValue)
        }
    }
    
    // CALLED AUTOMATICALLY when a device advertising our service UUID is discovered
    // peripheral - the device that was found (the ESP32)
    // advertisementData - extra info the device is broadcasting
    // rssi - signal strength
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        
        print("Discovered peripheral:", peripheral.name ?? "Unnamed device")
        print("RSSI:", RSSI)
        
        // Save the ESP32 so we can talk to it later
        connectedPeripheral = peripheral
        
        // Stop scanning - we found what we need
        centralManager.stopScan()
        print("Stopped scanning, attempting connection...")
        
        // Tell the iPhone to connect to the ESP32
        centralManager.connect(peripheral)
    }
    
    // CALLED AUTOMATICALLY when connection to ESP32 succeeds
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral:", peripheral.name ?? "Unnamed device")
        
        // Mark that we're connected - this makes the dot in the UI turn green
        isConnected = true
        
        // Set this class as the delegate for the peripheral
        peripheral.delegate = self
        
        // Ask the ESP32 for the service with our UUID
        peripheral.discoverServices([serviceUUID])
    }
    
    // CALLED AUTOMATICALLY if connection fails
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral:", peripheral.name ?? "Unnamed device")
        if let error {
            print("Connect error:", error.localizedDescription)
        }
        
        isConnected = false
        connectedPeripheral = nil
        targetCharacteristic = nil
        
        print("Restarting scan after failed connection...")
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }
    
    // CALLED AUTOMATICALLY when ESP32 disconnects (either on purpose or by accident)
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from peripheral:", peripheral.name ?? "Unnamed device")
        if let error {
            print("Disconnect error:", error.localizedDescription)
        }
        
        // Mark that we're disconnected
        isConnected = false
        connectedPeripheral = nil
        targetCharacteristic = nil
        
        // Immediately start scanning again to reconnect automatically
        print("Restarting scan...")
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }
    
    // CALLED AUTOMATICALLY when ESP32 tells us about its services
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            print("didDiscoverServices error:", error.localizedDescription)
            return
        }
        
        for service in peripheral.services ?? [] {
            print("Found service:", service.uuid.uuidString)
            
            // Ask for the characteristic inside this service
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }
    
    // CALLED AUTOMATICALLY when ESP32 tells us about characteristics inside a service
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            print("didDiscoverCharacteristicsFor error:", error.localizedDescription)
            return
        }
        
        for characteristic in service.characteristics ?? [] {
            print("Found characteristic:", characteristic.uuid.uuidString)
            
            // Check if this is OUR characteristic
            if characteristic.uuid == characteristicUUID {
                print("Matched target characteristic")
                
                // Save it so we can write to it later
                targetCharacteristic = characteristic
                
                // Subscribe to notifications from this characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    // CALLED AUTOMATICALLY when notification state changes
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            print("Notification state update error:", error.localizedDescription)
            return
        }
        
        print("Notifications enabled for characteristic:", characteristic.uuid.uuidString, characteristic.isNotifying)
    }
    
    // CALLED AUTOMATICALLY when ESP32 sends us data
    // This is how we receive button presses or any other messages from ESP32
    /*
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            print("didUpdateValueFor error:", error.localizedDescription)
            return
        }
        
        // characteristic.value is raw bytes (Data type)
        // We try to convert those bytes into a String using UTF-8 encoding
        if let data = characteristic.value, let message = String(data: data, encoding: .utf8) {
            print("Received from ESP32:", message)
            
            // All UI updates must happen on the main thread
            DispatchQueue.main.async {
                self.lastReceivedMessage = message
            }
        } else {
            print("Received non-text BLE data or empty value")
        }
    }
    */
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            print("didUpdateValueFor error:", error.localizedDescription)
            return
        }

        if let data = characteristic.value, let message = String(data: data, encoding: .utf8) {
            print("Received from ESP32:", message)

            DispatchQueue.main.async {
                self.lastReceivedMessage = message
                self.messageEventID = UUID()
            }
        } else {
            print("Received non-text BLE data or empty value")
        }
    }
    
    // Optional callback when a write with response succeeds/fails
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            print("Write failed for characteristic \(characteristic.uuid.uuidString):", error.localizedDescription)
        } else {
            print("Write acknowledged by ESP32 for characteristic:", characteristic.uuid.uuidString)
        }
    }
    
    // This is the function ContentView calls when it wants to send something to the ESP32
    // This can be:
    // - "PLAY"
    // - "PAUSE"
    // - "LYRIC:some line of text"
    func sendCommand(_ command: String) {
        // Prevent crashes or silent weirdness if we try to send before BLE is ready
        guard let peripheral = connectedPeripheral,
              let characteristic = targetCharacteristic else {
            print("sendCommand aborted - BLE not ready")
            return
        }
        
        guard let characteristic = targetCharacteristic else {
            print("sendCommand aborted - no target characteristic yet")
            return
        }
        
        // Convert the string into bytes (Data type)
        guard let data = command.data(using: .utf8) else {
            print("sendCommand aborted - could not encode command as UTF-8")
            return
        }
        
        print("Sending to ESP32:", command)
        print("Outgoing byte count:", data.count)
        
        // Write the bytes to the characteristic on the ESP32
        // .withResponse means the peripheral will acknowledge receipt
        //peripheral.writeValue(data, for: characteristic, type: .withResponse)
        DispatchQueue.main.async {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }
    
    func sendAudioChunk(_ chunk: Data) {
        guard let peripheral = connectedPeripheral else {
            print("sendAudioChunk aborted - no connected peripheral")
            return
        }
        
        guard let characteristic = targetCharacteristic else {
            print("sendAudioChunk aborted - no characteristic")
            return
        }
        
        let maxLength = peripheral.maximumWriteValueLength(for: .withoutResponse)
        
        guard chunk.count <= maxLength else {
            print("sendAudioChunk aborted - chunk too large: \(chunk.count) bytes, max is \(maxLength)")
            return
        }
        
        if !peripheral.canSendWriteWithoutResponse {
            print("Backpressure - retrying shortly")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                self.sendAudioChunk(chunk)
            }
            return
        }
        
        print("Sending audio chunk, bytes: \(chunk.count)")
        peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
    }
    
    func splitIntoChunks(_ data: Data, chunkSize: Int = 160) -> [Data] {
        guard chunkSize > 0 else { return [] }

        var chunks: [Data] = []
        var start = 0

        while start < data.count {
            let end = min(start + chunkSize, data.count)
            chunks.append(data.subdata(in: start..<end))
            start = end
        }

        return chunks
    }
    
    func debugSendStemAudioTimed(from fileURL: URL) {
        do {
            let pcmData = try AudioChunkLoader.loadPCM16MonoData(
                from: fileURL,
                targetSampleRate: 8_000
            )
            
            let chunks = self.splitIntoChunks(pcmData, chunkSize: 160)
            print("Prepared \(chunks.count) timed chunks")
            
            for (index, chunk) in chunks.enumerated() {
                let delay = DispatchTime.now() + .milliseconds(index * 20)
                DispatchQueue.main.asyncAfter(deadline: delay) {
                    print("Timed chunk \(index + 1)/\(chunks.count)")
                    self.sendAudioChunk(chunk)
                }
            }
        } catch {
            print("debugSendStemAudioTimed failed:", error.localizedDescription)
        }
    }
}
