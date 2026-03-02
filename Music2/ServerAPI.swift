//
//  ServerAPI.swift
//  Music2
//
//  Created by grace keywork on 3/2/26.
//

import Foundation

// ServerAPI is the single place where the app talks to Lucas's server
// Every network call goes through here - nothing else in the app should make HTTP requests
// 'final' means no other class can inherit from this one (just a safety/clarity choice)
final class ServerAPI {

    // ── CONFIGURATION ─────────────────────────────────────────────────────────
    
    // Lucas's server address - swap this string when he has a real server running
    // Currently points to a local machine on the school network
    let baseURL = URL(string: "http://10.5.22.60:8000")!

    // Master switch for mock data
    // true  = all fetch functions return fake hardcoded data (no server needed)
    // false = all fetch functions hit Lucas's real endpoints
    // Flip this to false once Lucas has his server running
    var useMockData: Bool = true

    // ── UPLOAD ────────────────────────────────────────────────────────────────
    
    // Sends a WAV file to Lucas's server for processing
    // Lucas's server will run stem separation (Demucs) and lyric extraction on it
    // Returns the song_id Lucas assigns to it - we'll need that ID for all future requests
    // Returns nil for now until Lucas sets up the response JSON
    func uploadSong(fileURL: URL) async throws -> String? {

        // iOS sandboxes file access for security - files picked from the file picker
        // need explicit permission to be read. startAccessingSecurityScopedResource()
        // unlocks that permission, and defer ensures we always release it when done
        guard fileURL.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "ServerAPI", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not access selected file"])
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        // Read the entire WAV file into memory as raw bytes
        let audioData = try Data(contentsOf: fileURL)

        // Build the full URL: baseURL + "/uploadfile/"
        let uploadURL = baseURL.appendingPathComponent("uploadfile/")
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"

        // Multipart form is the standard HTTP format for file uploads
        // A boundary is a unique string that separates different parts of the form
        // It must be unique enough that it won't appear inside the file data itself
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type")

        // Build the request body manually following multipart/form-data format
        var body = Data()

        // Each "part" starts with --boundary
        body.append("--\(boundary)\r\n".data(using: .utf8)!)

        // Tell the server this part is a file, what the form field is called ("file"),
        // and what the filename is - Lucas's server reads the field named "file"
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        
        // Tell the server what kind of data is in this part
        // \r\n\r\n (double line break) marks the end of headers, start of actual data
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)

        // The actual WAV file bytes
        body.append(audioData)

        // Final boundary with -- on both ends signals end of the entire form
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // Send the request and wait for Lucas's server to respond
        // async/await means the app stays responsive while waiting - no freezing
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        // Make sure we got an HTTP response (not some other kind of network response)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // HTTP 200-299 = success, anything else = something went wrong on Lucas's server
        // We include the server's error text in our error message to help with debugging
        guard (200...299).contains(http.statusCode) else {
            let serverText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "ServerAPI", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Upload failed (\(http.statusCode)). \(serverText)"])
        }

        // TODO: once Lucas returns {"song_id": "abc123"} in his response,
        // parse it here and return the ID so we can use it in future requests
        return nil
    }

    // ── MOCK / PLACEHOLDER FUNCTIONS ──────────────────────────────────────────
    // These functions return fake data so we can build and test the app
    // without needing Lucas's server to be ready
    // Each one will be replaced with a real HTTP request when Lucas is ready

    // Returns the list of songs available in the library
    // Real version will be: GET /library/ → JSON array of Song objects
    func fetchLibrary() async throws -> [Song] {
        if useMockData {
            return [Song(id: "mock_song_001", title: "Test Song (Local WAV)", durationSec: 10)]
        }
        throw URLError(.unsupportedURL)  // placeholder until real endpoint exists
    }

    // Returns timestamped lyric lines for a given song
    // Real version will be: GET /lyrics/{songID} → JSON array of LyricLine objects
    // These get sent over BLE to Caitlyn's glasses display during playback
    func fetchLyrics(songID: String) async throws -> [LyricLine] {
        if useMockData {
            return [
                LyricLine(timeMs: 500,  text: "Line 1 (mock)"),
                LyricLine(timeMs: 2500, text: "Line 2 (mock)"),
                LyricLine(timeMs: 4500, text: "Line 3 (mock)")
            ]
        }
        throw URLError(.unsupportedURL)  // placeholder until real endpoint exists
    }

    // Returns raw audio bytes for one chunk of one stem of one song
    // Real version will be: GET /stems/{songID}/{stem}/{chunkIndex}
    // This is the most important function - it powers the haptic streaming pipeline
    //
    // songID     - which song (from fetchLibrary or after upload)
    // stem       - which instrument track: .drums, .bass, .vocals, or .other
    // chunkIndex - which 5-second piece we want (0 = first 5 sec, 1 = next 5 sec, etc.)
    // format     - the audio spec we expect: 48000 Hz, mono, 16-bit, 5-sec chunks
    func fetchStemChunk(songID: String, stem: StemType, chunkIndex: Int, format: AudioFormat) async throws -> Data {
        if useMockData {
            
            // Load a WAV file we've bundled inside the app for testing
            // This file is called "test.wav" and lives in the Xcode project's bundle
            // In real use, this data would come over the network from Lucas
            guard let wavURL = Bundle.main.url(forResource: "test", withExtension: "wav") else {
                throw NSError(domain: "ServerAPI", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Bundled test.wav not found"])
            }
            let wavData = try Data(contentsOf: wavURL)

            // WAV files start with a 44-byte header describing the audio format
            // We skip it because we only want the raw PCM audio bytes
            // Lucas should send us raw PCM with no header, so this step won't be needed later
            let headerBytes = 44
            guard wavData.count > headerBytes else { return Data() }
            let pcm = wavData.subdata(in: headerBytes..<wavData.count)

            // Calculate how many bytes = one chunk based on the AudioFormat agreement
            // bitsPerSample / 8 converts bits to bytes (16 bits = 2 bytes per sample)
            // bytesPerSecond = how many bytes of audio pass by every second
            // chunkBytes = how many bytes make up one 5-second chunk
            let bytesPerSample  = format.bitsPerSample / 8
            let bytesPerSecond  = format.sampleRate * format.channels * bytesPerSample
            let chunkBytes      = format.chunkDurationSec * bytesPerSecond

            // Find where this chunk starts and ends in the full PCM data
            let start = chunkIndex * chunkBytes
            if start >= pcm.count { return Data() }  // requested chunk is past end of file
            let end = min(start + chunkBytes, pcm.count)

            // Debug info printed to Xcode console - helpful for verifying the math
            let pcmSeconds = Double(pcm.count) / Double(bytesPerSecond)
            print("WAV total bytes:", wavData.count)
            print("PCM bytes (no header):", pcm.count)
            print("PCM duration (assumed 48kHz mono 16bit):", pcmSeconds, "seconds")

            // Return just the bytes for this specific chunk
            return pcm.subdata(in: start..<end)
        }

        throw URLError(.unsupportedURL)  // placeholder until real endpoint exists
    }
}
