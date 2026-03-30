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
    // let baseURL = URL(string: "http://10.5.22.60:8000")!
    //let baseURL = URL(string: "http://192.168.68.57:8000")!
    //192.168.68.57
    
    let baseURL = URL(string: "http://192.168.68.59:8000")!

    //let baseURL = URL(string: "http://10.4.69.53:8000")!

    // ── RESPONSE MODELS ───────────────────────────────────────────────────────

    // This matches the JSON Lucas's backend returns after upload
    // Example:
    // {
    //   "success": true,
    //   "message": "Upload and processing complete",
    //   "song_name": "My Song",
    //   "artist": "My Artist"
    // }
    struct UploadResponse: Codable {
        let success: Bool
        let message: String?
        let song_name: String?
        let artist: String?
        let error: String?
    }
    
    struct SongExistsResponse: Codable {
        let exists: Bool
        let song_name: String
        let artist: String
    }

    /*func checkSongExists(songTitle: String, artist: String) async throws -> Bool {
        let url = baseURL
            .appendingPathComponent("song_exists")
            .appendingPathComponent(songTitle)
            .appendingPathComponent(artist)

        print("Checking if song exists at:", url.absoluteString)

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            let serverText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "ServerAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Song exists check failed (\(http.statusCode)). \(serverText)"]
            )
        }

        let decoded = try JSONDecoder().decode(SongExistsResponse.self, from: data)
        return decoded.exists
    }
     */
    // ── UPLOAD ────────────────────────────────────────────────────────────────

    // Sends a WAV file to Lucas's server for processing
    // Lucas's server will run stem separation (Demucs) and lyric extraction on it
    // Returns the parsed upload response so the UI can create a library item
    func uploadSong(fileURL: URL) async throws -> UploadResponse {
        print("uploadSong called")
        print("Selected file:", fileURL.lastPathComponent)
        print("Uploading to:", baseURL.appendingPathComponent("uploadfile/").absoluteString)

        // iOS sandboxes file access for security - files picked from the file picker
        // need explicit permission to be read. startAccessingSecurityScopedResource()
        // unlocks that permission, and defer ensures we always release it when done
        guard fileURL.startAccessingSecurityScopedResource() else {
            throw NSError(
                domain: "ServerAPI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not access selected file"]
            )
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        // Read the entire WAV file into memory as raw bytes
        //let audioData = try Data(contentsOf: fileURL)
        let audioData = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: fileURL)
        }.value
        print("Audio data bytes:", audioData.count)

        // Build the full URL: baseURL + "/uploadfile/"
        let uploadURL = baseURL.appendingPathComponent("uploadfile/")
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"

        // Multipart form is the standard HTTP format for file uploads
        // A boundary is a unique string that separates different parts of the form
        // It must be unique enough that it won't appear inside the file data itself
        let boundary = UUID().uuidString
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        // Build the request body manually following multipart/form-data format
        var body = Data()

        // Each "part" starts with --boundary
        body.append("--\(boundary)\r\n".data(using: .utf8)!)

        // Tell the server this part is a file, what the form field is called ("file"),
        // and what the filename is - Lucas's server reads the field named "file"
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n"
                .data(using: .utf8)!
        )

        // Tell the server what kind of data is in this part
        // \r\n\r\n (double line break) marks the end of headers, start of actual data
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)

        // The actual WAV file bytes
        body.append(audioData)

        // Final boundary with -- on both ends signals end of the entire form
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // Send the request and wait for Lucas's server to respond
        // async/await means the app stays responsive while waiting - no freezing
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 3600

        let session = URLSession(configuration: config)
        let (data, response) = try await session.upload(for: request, from: body)

        // Make sure we got an HTTP response (not some other kind of network response)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        print("Upload status code:", http.statusCode)
        print("Upload URL:", uploadURL.absoluteString)
        print("Filename sent:", fileURL.lastPathComponent)

        if let responseText = String(data: data, encoding: .utf8) {
            print("Upload response text:", responseText)
        }

        // HTTP 200-299 = success, anything else = something went wrong on Lucas's server
        // We include the server's error text in our error message to help with debugging
        guard (200...299).contains(http.statusCode) else {
            let serverText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "ServerAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Upload failed (\(http.statusCode)). \(serverText)"]
            )
        }

        if let responseText = String(data: data, encoding: .utf8) {
            print("Upload response text:", responseText)

            let cleaned = responseText.trimmingCharacters(in: .whitespacesAndNewlines)

            if cleaned == "true" || cleaned == "True" {
                return UploadResponse(
                    success: true,
                    message: "Upload and processing complete",
                    song_name: nil,
                    artist: nil,
                    error: nil
                )
            }

            if cleaned.contains("Song already exists") {
                return UploadResponse(
                    success: true,
                    message: "Song already exists",
                    song_name: nil,
                    artist: nil,
                    error: nil
                )
            }
        }

        throw NSError(
            domain: "ServerAPI",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unexpected upload response from server"]
        )

    }

    // ── LIBRARY ───────────────────────────────────────────────────────────────

    // There is not yet a real backend /library/ endpoint.
    // For tomorrow's demo, the app will maintain the visible library locally
    // after successful uploads during the current app session.
    func fetchLibrary() async throws -> [Song] {
        return []
    }

    // ── LOCAL STEM ACCESS ─────────────────────────────────────────────────────

    // Returns raw audio bytes for one chunk of one previously-downloaded local stem WAV
    // This is useful for later chunked playback / haptics work
    //
    // songID     - currently used as the song title in this project
    // stem       - which instrument track: .drums, .bass, .vocals, or .other
    // chunkIndex - which 5-second piece we want (0 = first 5 sec, 1 = next 5 sec, etc.)
    // format     - the audio spec we expect
    func fetchStemChunk(songID: String, stem: StemType, chunkIndex: Int, format: AudioFormat) async throws -> Data {
        let wavURL = localStemURL(songTitle: songID, stem: stem)

        guard FileManager.default.fileExists(atPath: wavURL.path) else {
            throw NSError(
                domain: "ServerAPI",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Downloaded stem WAV not found at \(wavURL.path)"]
            )
        }

        //let wavData = try Data(contentsOf: wavURL)
        let wavData = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: wavURL)
        }.value

        // WAV files start with a 44-byte header describing the audio format
        // We skip it because we only want the raw PCM audio bytes
        let headerBytes = 44
        guard wavData.count > headerBytes else { return Data() }

        let pcm = wavData.subdata(in: headerBytes..<wavData.count)

        // Calculate how many bytes = one chunk based on the AudioFormat agreement
        let bytesPerSample = format.bitsPerSample / 8
        let bytesPerSecond = format.sampleRate * format.channels * bytesPerSample
        let chunkBytes = format.chunkDurationSec * bytesPerSecond

        let start = chunkIndex * chunkBytes
        if start >= pcm.count { return Data() }

        let end = min(start + chunkBytes, pcm.count)

        print("Reading local stem WAV:", wavURL.lastPathComponent)
        print("WAV total bytes:", wavData.count)
        print("PCM bytes:", pcm.count)
        print("Returning chunk \(chunkIndex), bytes \(start)..<\(end)")

        return pcm.subdata(in: start..<end)
    }
    
    

    // ── STEM DOWNLOAD ─────────────────────────────────────────────────────────

    // Downloads an entire stem WAV from Lucas's backend and saves it into
    // the app's Documents directory so we can reuse it later
    func downloadFullStem(songTitle: String, stem: StemType) async throws -> URL {

        let stemName: String
        switch stem {
        case .drums: stemName = "drums"
        case .bass: stemName = "bass"
        case .vocals: stemName = "vocals"
        case .other: stemName = "guitar"
        }

        let url = baseURL
            .appendingPathComponent("requests")
            .appendingPathComponent(songTitle)
            .appendingPathComponent(stemName)

        print("Downloading stem from:", url.absoluteString)

        let (tempURL, response) = try await URLSession.shared.download(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        print("Stem download status code:", http.statusCode)
        print("Stem MIME type:", http.value(forHTTPHeaderField: "Content-Type") ?? "nil")

        //let tempData = try Data(contentsOf: tempURL)
        let tempData = try await Task.detached(priority: .utility) {
            try Data(contentsOf: tempURL)
        }.value
        print("Temp downloaded size:", tempData.count)

        if let text = String(data: tempData, encoding: .utf8), tempData.count < 500 {
            print("Temp downloaded text response:", text)
        }

        guard (200...299).contains(http.statusCode) else {
            let serverText = String(data: tempData, encoding: .utf8) ?? ""
            throw NSError(
                domain: "ServerAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Stem download failed (\(http.statusCode)). \(serverText)"]
            )
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let localURL = docs.appendingPathComponent("\(songTitle)_\(stemName).wav")

        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }

        try FileManager.default.moveItem(at: tempURL, to: localURL)

        //let savedData = try Data(contentsOf: localURL)
        let savedData = try await Task.detached(priority: .utility) {
            try Data(contentsOf: localURL)
        }.value
        print("Saved stem size:", savedData.count)
        print("Saved stem path:", localURL.path)

        return localURL
    }

    // Returns the local file path where a previously-downloaded stem WAV should live
    func localStemURL(songTitle: String, stem: StemType) -> URL {
        let stemName: String
        switch stem {
        case .drums: stemName = "drums"
        case .bass: stemName = "bass"
        case .vocals: stemName = "vocals"
        case .other: stemName = "guitar"
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("\(songTitle)_\(stemName).wav")
    }
    
    /*
    func getOrDownloadStem(songTitle: String, stem: StemType) async throws -> URL {
        let localURL = localStemURL(songTitle: songTitle, stem: stem)

        if FileManager.default.fileExists(atPath: localURL.path) {
            print("Using cached local stem:", localURL.path)
            return localURL
        }

        print("Local stem not found, downloading from server...")
        return try await downloadFullStem(songTitle: songTitle, stem: stem)
    }
     */
    func getOrDownloadStem(songTitle: String, stem: StemType) async throws -> URL {
        print("Forcing fresh download from server for:", stem, "of", songTitle)
        return try await downloadFullStem(songTitle: songTitle, stem: stem)
    }

    // ── LYRICS ────────────────────────────────────────────────────────────────

    // Fetches the plain text lyric file Lucas's backend currently returns
    // For tomorrow's demo, these are sent over BLE line by line at a fixed interval
    func fetchLyrics(songTitle: String) async throws -> [String] {

        let url = baseURL
            .appendingPathComponent("requests")
            .appendingPathComponent("\(songTitle)_lyrics")

        print("Fetching lyrics from:", url.absoluteString)

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        print("Lyrics status code:", http.statusCode)

        guard (200...299).contains(http.statusCode) else {
            let serverText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "ServerAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Lyrics fetch failed (\(http.statusCode)). \(serverText)"]
            )
        }

        let text = String(data: data, encoding: .utf8) ?? ""

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        print("Fetched lyric lines:", lines.count)

        return lines
    }
}
