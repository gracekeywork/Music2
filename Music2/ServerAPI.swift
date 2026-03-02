//
//  ServerAPI 2.swift
//  Music2
//
//  Created by grace keywork on 3/2/26.
//


import Foundation

final class ServerAPI {

    // Change this to Lucas’s server later
    let baseURL = URL(string: "http://10.5.22.60:8000")!

    // Turn this OFF when Lucas endpoints exist
    var useMockData: Bool = true

    // MARK: - Upload

    // Uploads a WAV file to the server.
    // Returns: (songID?) if the server provides one, else nil for now.
    func uploadSong(fileURL: URL) async throws -> String? {

        // iOS file picker URLs often require security-scoped access
        guard fileURL.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "ServerAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not access selected file"])
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        let audioData = try Data(contentsOf: fileURL)

        let uploadURL = baseURL.appendingPathComponent("uploadfile/")
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Start boundary
        body.append("--\(boundary)\r\n".data(using: .utf8)!)

        // IMPORTANT: correct headers (Disposition + Type)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)

        // File bytes
        body.append(audioData)

        // End boundary
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // URLSession async/await
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            let serverText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "ServerAPI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Upload failed (\(http.statusCode)). \(serverText)"])
        }

        // If Lucas returns JSON with a song_id, parse it here later.
        // For now return nil.
        return nil
    }

    // MARK: - Mock / placeholders for now

    func fetchLibrary() async throws -> [Song] {
        if useMockData {
            return [Song(id: "mock_song_001", title: "Test Song (Local WAV)", durationSec: 10)]
        }
        throw URLError(.unsupportedURL)
    }

    func fetchLyrics(songID: String) async throws -> [LyricLine] {
        if useMockData {
            return [
                LyricLine(timeMs: 500, text: "Line 1 (mock)"),
                LyricLine(timeMs: 2500, text: "Line 2 (mock)"),
                LyricLine(timeMs: 4500, text: "Line 3 (mock)")
            ]
        }
        throw URLError(.unsupportedURL)
    }

    /// Returns PCM bytes for one chunk (mock: slices from a bundled WAV).
    func fetchStemChunk(songID: String, stem: StemType, chunkIndex: Int, format: AudioFormat) async throws -> Data {
        if useMockData {
            // Rename to your actual test wav name:
            guard let wavURL = Bundle.main.url(forResource: "test_haptic", withExtension: "wav") else {
                throw NSError(domain: "ServerAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bundled test_haptic.wav not found"])
            }
            let wavData = try Data(contentsOf: wavURL)

            // For typical PCM WAVs, header is often 44 bytes (good for your demo file).
            // Later, Lucas should ideally send raw PCM and you won't need this.
            let headerBytes = 44
            guard wavData.count > headerBytes else { return Data() }

            let pcm = wavData.subdata(in: headerBytes..<wavData.count)

            let bytesPerSample = format.bitsPerSample / 8
            let bytesPerSecond = format.sampleRate * format.channels * bytesPerSample
            let chunkBytes = format.chunkDurationSec * bytesPerSecond

            let start = chunkIndex * chunkBytes
            if start >= pcm.count { return Data() }

            let end = min(start + chunkBytes, pcm.count)
            return pcm.subdata(in: start..<end)
        }

        throw URLError(.unsupportedURL)
    }
}
