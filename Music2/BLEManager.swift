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
    
 
    
    // ! means "this will definitely have a value before anyone uses it, trust me"
    // We use ! because we can't create it until inside init()
    //var centralManager: CBCentralManager!       // The object that controls your iPhone's Bluetooth radio
                                                 // Handles scanning, connecting, disconnecting
    lazy var centralManager: CBCentralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    
    // ? means "this might be nil (empty) if we haven't found the ESP32 yet"
    var connectedPeripheral: CBPeripheral?      // The ESP32 device once we find and connect to it
    var targetCharacteristic: CBCharacteristic? // The specific data channel inside the ESP32 we talk through
    
    // These are the UUIDs that Caitlyn must match exactly on the ESP32 side
    // Service UUID - identifies the overall BLE service on ESP32
    let serviceUUID = CBUUID(string: "62e80d9b-5a2c-4bae-b4a0-02627fc00e7b")
    // Characteristic UUID - identifies the specific data channel we read/write to
    let characteristicUUID = CBUUID(string: "d4aff33c-2366-47c1-8460-3cc0b19517e6")
    
    // @Published means "whenever this value changes, tell the UI to update automatically"
    // So when isConnected flips from false to true, the dot in the UI instantly turns green
    @Published var isConnected = false           // true when connected to ESP32, false when not
    @Published var lastReceivedMessage = ""      // Stores the last message received from ESP32
    
    

    
    // This runs automatically when BLEManager() is created
    // It sets up the Bluetooth manager and starts listening for BLE events
    override init() {
        super.init()  // Required for NSObject - calls the parent class's init
        print("BLEManager init() called")
        _ = centralManager // this triggers the lazy var to actually initialize
        print("centralManager state: \(centralManager.state.rawValue)")
    }
    
    
   
    // These functions are called automatically by CoreBluetooth at specific moments
    // We don't call them ourselves - Apple's framework calls them for us
    
    // CALLED AUTOMATICALLY when Bluetooth state changes (on/off/unavailable/etc)
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print(" didUpdateState fired")
        print("Bluetooth state raw:", central.state.rawValue)
        // Check if Bluetooth is powered on and ready to use
        if central.state == .poweredOn {
            // Start scanning for any device advertising our specific service UUID
            // This is like shouting "is anyone out there with service 62e80d9b...?"
            // Only devices with this exact service UUID will respond
            centralManager.scanForPeripherals(withServices: [serviceUUID])
        }
        // If Bluetooth is off (.poweredOff) or unavailable, this just does nothing
        // The app will automatically start scanning once Bluetooth turns back on
    }
    
    // CALLED AUTOMATICALLY when a device advertising our service UUID is discovered
    // peripheral - the device that was found (the ESP32)
    // advertisementData - extra info the device is broadcasting (we don't use this)
    // rssi - signal strength (we don't use this, but could use it to show distance)
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Save the ESP32 so we can talk to it later
        connectedPeripheral = peripheral
        
        // Stop scanning - we found what we need, no point wasting battery
        centralManager.stopScan()
        
        // Tell the iPhone to connect to the ESP32
        // This doesn't happen instantly - connection takes ~100ms
        // When connection succeeds, didConnect (below) will be called automatically
        centralManager.connect(peripheral)
    }
    
    // CALLED AUTOMATICALLY when connection to ESP32 succeeds
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Mark that we're connected - this makes the dot in the UI turn green
        isConnected = true
        
        // Set this class as the delegate for the peripheral
        // This means "send peripheral events (like data received) back to this class"
        peripheral.delegate = self
        
        // Ask the ESP32 "do you have a service with UUID 62e80d9b...?"
        // When ESP32 responds, didDiscoverServices (below) will be called
        peripheral.discoverServices([serviceUUID])
    }
    
    // CALLED AUTOMATICALLY when ESP32 disconnects (either on purpose or by accident)
    // error - tells us why it disconnected (we don't use this, but could log it for debugging)
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Mark that we're disconnected - this makes the dot turn red
        isConnected = false
        
        // Immediately start scanning again to reconnect automatically
        // This is why the app can recover from connection drops without user intervention
        centralManager.scanForPeripherals(withServices: [serviceUUID])
    }
    
    
    // These are also called automatically by CoreBluetooth
    
    // CALLED AUTOMATICALLY when ESP32 tells us about its services
    // At this point we've found the service with our UUID, now we need to look inside it for characteristics
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        // Loop through each service the ESP32 has
        // ?? [] means "if services is nil, use an empty array instead" (prevents crashes)
        for service in peripheral.services ?? [] {
            // For each service, ask "do you have a characteristic with UUID d4aff33c...?"
            // When ESP32 responds, didDiscoverCharacteristicsFor (below) will be called
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }
    
    // CALLED AUTOMATICALLY when ESP32 tells us about characteristics inside a service
    // At this point we've found our specific characteristic - the data channel we'll use
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Loop through each characteristic in the service
        for characteristic in service.characteristics ?? [] {
            // Check if this is OUR characteristic (the one with our UUID)
            if characteristic.uuid == characteristicUUID {
                // Save it so we can write to it later when sending commands
                targetCharacteristic = characteristic
                
                // Subscribe to notifications from this characteristic
                // This tells ESP32 "whenever you have data to send me, send it to this characteristic"
                // Now when ESP32 sends anything, didUpdateValueFor (below) will be called
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    // CALLED AUTOMATICALLY when ESP32 sends us data
    // This is how we receive button presses or any other messages from ESP32
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // if let means "if characteristic.value exists and isn't nil, unwrap it and use it"
        // characteristic.value is raw bytes (Data type)
        // We try to convert those bytes into a String using UTF-8 encoding
        if let data = characteristic.value, let message = String(data: data, encoding: .utf8) {
            // DispatchQueue.main.async means "run this code on the main thread"
            // REQUIRED: All UI updates in iOS MUST happen on the main thread
            // BLE events happen on a background thread, so we have to switch to main
            DispatchQueue.main.async {
                // Update the lastReceivedMessage variable
                // Because it's @Published, the UI will automatically update to show the new message
                self.lastReceivedMessage = message
            }
        }
        // If the data couldn't be converted to a string, just ignore it
    }
    
    
    // This is the function ContentView calls when you press the play/pause button
    // command - either "PLAY" or "PAUSE" as a string
    func sendCommand(_ command: String) {
        // guard let means "if EITHER of these is nil, immediately return and do nothing"
        // This prevents crashes if we try to send before we're connected
        guard let peripheral = connectedPeripheral, let characteristic = targetCharacteristic else { return }
        
        // Convert the string into bytes (Data type)
        // ! means "force unwrap" - we know this will succeed because strings can always convert to UTF-8
        let data = command.data(using: .utf8)!
        
        // Write the bytes to the characteristic on the ESP32
        // type: .withResponse means "wait for ESP32 to acknowledge it received the data"
        // This is more reliable than .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
}
