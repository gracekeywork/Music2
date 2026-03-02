//
//  ContentView.swift
//  Music2
//
//  Created by grace keywork on 2/16/26.
//

import SwiftUI                    // Apple's UI framework - everything visual lives here
import UniformTypeIdentifiers     // Lets us filter the file picker to only show audio files

struct ContentView: View {
    
    // bleManager is shared across the whole app - it handles all Bluetooth communication
    // @EnvironmentObject means it was injected at the app root, not created here
    @EnvironmentObject var bleManager: BLEManager
    
    // api handles all communication with Lucas's server (uploads, fetching stems, lyrics)
    private let api = ServerAPI()
    
    // Local UI state - @State means SwiftUI re-renders the view whenever these change
    @State private var isPlaying = false        // tracks whether music is playing or paused
    @State private var showFilePicker = false   // controls whether the file picker is open
    @State private var uploadStatus = ""        // message shown to user about upload progress

    var body: some View {
        ZStack {
            // Black background that fills the whole screen including safe areas
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                
                // ── CONNECTION STATUS DOT ─────────────────────────────────
                // Top right corner: green dot = connected, red = scanning
                // bleManager.isConnected is @Published so this updates automatically
                HStack {
                    Spacer()
                    Circle()
                        .fill(bleManager.isConnected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    Text(bleManager.isConnected ? "Connected" : "Scanning...")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // ── TITLE ─────────────────────────────────────────────────
                Text("Music2")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                // ── PLAY/PAUSE BUTTON ─────────────────────────────────────
                // Tapping toggles isPlaying, then sends "PLAY" or "PAUSE" over BLE
                // to Caitlyn's ESP32, which will trigger/stop the haptic transducers
                // Button is greyed out and untappable if BLE is not connected
                Button(action: {
                    isPlaying.toggle()
                    bleManager.sendCommand(isPlaying ? "PLAY" : "PAUSE")
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                        .frame(width: 120, height: 120)
                        .background(isPlaying ? Color.purple : Color.gray)
                        .clipShape(Circle())
                        .animation(.easeInOut, value: isPlaying)  // smooth color transition
                }
                .disabled(!bleManager.isConnected)
                
                // ── BUTTON PRESS COUNTER ──────────────────────────────────
                // The ESP32 sends back messages like "BUTTON_PRESSED:3"
                // We strip the label and show just the number
                // This whole block is hidden if no message has been received yet
                if !bleManager.lastReceivedMessage.isEmpty {
                    let count = bleManager.lastReceivedMessage
                        .replacingOccurrences(of: "BUTTON_PRESSED:", with: "")
                    Text("Button presses: \(count)")
                        .foregroundColor(.green)
                        .font(.caption)
                        .padding()
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(10)
                }
                
                // ── UPLOAD WAV BUTTON ─────────────────────────────────────
                // Opens iOS file picker filtered to audio files
                // Once user picks a file, uploadWAV() is called with its URL
                Button("Upload WAV") {
                    showFilePicker = true
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(8)
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [UTType.audio],   // only show audio files
                    allowsMultipleSelection: false          // one file at a time
                ) { result in
                    // result is either the picked URL or an error - we only proceed if success
                    if let url = try? result.get().first {
                        uploadWAV(url: url)
                    }
                }
                
                // ── UPLOAD STATUS MESSAGE ─────────────────────────────────
                // Shows "Uploading...", "Uploaded!", or an error message
                // Hidden entirely when uploadStatus is empty
                if !uploadStatus.isEmpty {
                    Text(uploadStatus)
                        .foregroundColor(.white)
                        .font(.caption)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
            
            // ── DEV/TEST BUTTON ───────────────────────────────────────────
            // This button is for testing the full data pipeline WITHOUT Lucas's server
            // It uses mock data from ServerAPI (useMockData = true) and a bundled test WAV
            // NOT a user-facing feature - just for development and demo purposes
            Button("Test Pipeline (No Server)") {
                Task {   // Task lets us run async code from a button press
                    do {
                        // Step 1: Get fake song library (returns one mock song)
                        let songs = try await api.fetchLibrary()
                        guard let song = songs.first else {
                            uploadStatus = "No mock songs"
                            return
                        }

                        // Step 2: Define the audio format we expect from Lucas
                        // 48000 Hz, mono, 16-bit, 5-second chunks
                        let format = AudioFormat(sampleRate: 48000, channels: 1, bitsPerSample: 16, chunkDurationSec: 5)

                        // Step 3: Fetch 3 chunks of the drums stem from the mock/bundled WAV
                        // In real use, these would come from Lucas's server
                        let chunk0 = try await api.fetchStemChunk(songID: song.id, stem: .drums, chunkIndex: 0, format: format)
                        let chunk1 = try await api.fetchStemChunk(songID: song.id, stem: .drums, chunkIndex: 1, format: format)
                        let chunk2 = try await api.fetchStemChunk(songID: song.id, stem: .drums, chunkIndex: 2, format: format)

                        // Step 4: Save chunk 0 to temp storage on disk
                        // This simulates what will happen during real playback streaming
                        let savedURL = try TempStorage.writeChunk(songID: song.id, stem: .drums, chunkIndex: 0, data: chunk0, ext: "pcm")

                        // Step 5: Fetch fake lyrics (3 hardcoded lines with timestamps)
                        let lyrics = try await api.fetchLyrics(songID: song.id)

                        // Show a summary of everything that happened on screen
                        uploadStatus = """
                        Mock OK 
                        chunk0 bytes: \(chunk0.count)
                        chunk1 bytes: \(chunk1.count)
                        chunk2 bytes: \(chunk2.count)
                        saved: \(savedURL.lastPathComponent)
                        lyrics lines: \(lyrics.count)
                        """
                        print("Saved chunk at:", savedURL)

                    } catch {
                        uploadStatus = "Test error: \(error.localizedDescription)"
                    }
                }
            }
            .padding()
        }
    }
    
    // ── UPLOAD FUNCTION ───────────────────────────────────────────────────
    // Called when user picks a WAV file from the file picker
    // Hands off to ServerAPI which handles the actual HTTP multipart upload to Lucas's server
    // uploadStatus is shown in the UI so the user knows what's happening
    func uploadWAV(url: URL) {
        uploadStatus = "Uploading..."

        Task {
            do {
                _ = try await api.uploadSong(fileURL: url)
                uploadStatus = "Uploaded!"
            } catch {
                uploadStatus = "Error: \(error.localizedDescription)"
            }
        }
    }
}

// Preview lets you see the UI in Xcode without running the app
// We inject a fake BLEManager so the preview doesn't try to actually use Bluetooth
#Preview {
    ContentView()
        .environmentObject(BLEManager())
}
