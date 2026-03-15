//
//  ContentView.swift
//  Music2
//
//  Created by grace keywork on 2/16/26.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct ContentView: View {
    
    @EnvironmentObject var bleManager: BLEManager
    private let api = ServerAPI()
    
    // Current now-playing state for home screen
    @State private var currentSong: Song? = nil
    @State private var currentStem: StemType? = nil
    @State private var isPlaying = false
    
    // Library / upload state
    @State private var librarySongs: [Song] = []
    @State private var showFilePicker = false
    @State private var uploadStatus = ""
    @State private var isLoadingLibrary = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // MARK: - Header
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Music2")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text("Haptic music experience")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(bleManager.isConnected ? Color.green : Color.red)
                                    .frame(width: 10, height: 10)
                                
                                Text(bleManager.isConnected ? "Connected" : "Scanning...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                        }
                        
                        // MARK: - Now Playing Card
                        if currentSong != nil && currentStem != nil {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Now Playing")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                HStack(spacing: 16) {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(nowPlayingGradient)
                                        .frame(width: 90, height: 90)
                                        .overlay(
                                            Image(systemName: "waveform")
                                                .font(.system(size: 30))
                                                .foregroundColor(.white)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(currentSong?.title ?? "")
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                        
                                        Text(nowPlayingSubtitle)
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                }
                                
                                HStack {
                                    Button(action: {
                                        togglePlaybackFromHome()
                                    }) {
                                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(.white)
                                            .frame(width: 60, height: 60)
                                            .background(homePlayButtonColor)
                                            .clipShape(Circle())
                                    }
                                    .disabled(!canControlPlayback)
                                    .opacity(canControlPlayback ? 1.0 : 0.5)
                                    
                                    Spacer()
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(20)
                        }
                        
                        // MARK: - Library Header
                        HStack {
                            Text("Library")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button(action: {
                                loadLibrary()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Refresh")
                                }
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(10)
                            }
                        }
                        
                        // MARK: - Upload Button
                        Button(action: {
                            showFilePicker = true
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Upload WAV to Library")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(14)
                        }
                        .fileImporter(
                            isPresented: $showFilePicker,
                            allowedContentTypes: [UTType.audio],
                            allowsMultipleSelection: false
                        ) { result in
                            if let url = try? result.get().first {
                                uploadWAV(url: url)
                            }
                        }
                        
                        // MARK: - Upload / Debug Status
                        if !uploadStatus.isEmpty {
                            Text(uploadStatus)
                                .foregroundColor(.white)
                                .font(.subheadline)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(12)
                        }
                        
                        // MARK: - Library List
                        if isLoadingLibrary {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical)
                        } else if librarySongs.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No songs in library yet")
                                    .foregroundColor(.white)
                                    .font(.headline)
                                
                                Text("Upload a song or refresh the library to load available tracks.")
                                    .foregroundColor(.gray)
                                    .font(.subheadline)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(16)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(librarySongs) { song in
                                    NavigationLink {
                                        SongDetailView(
                                            song: song,
                                            bleConnected: bleManager.isConnected,
                                            currentSong: currentSong,
                                            currentStem: currentStem,
                                            onPlayStem: { chosenSong, chosenStem in
                                                startPlayback(song: chosenSong, stem: chosenStem)
                                            }
                                        )
                                    } label: {
                                        HStack(spacing: 14) {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.12))
                                                .frame(width: 56, height: 56)
                                                .overlay(
                                                    Image(systemName: "music.note")
                                                        .foregroundColor(.white)
                                                )
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(song.title)
                                                    .foregroundColor(.white)
                                                    .font(.headline)
                                                    .multilineTextAlignment(.leading)
                                                
                                                if let duration = song.durationSec {
                                                    Text(String(format: "%.0f sec", duration))
                                                        .foregroundColor(.gray)
                                                        .font(.caption)
                                                } else {
                                                    Text("Tap to choose stem")
                                                        .foregroundColor(.gray)
                                                        .font(.caption)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            if currentSong?.id == song.id {
                                                Image(systemName: "speaker.wave.2.fill")
                                                    .foregroundColor(.green)
                                                    .font(.title3)
                                            } else {
                                                Image(systemName: "chevron.right")
                                                    .foregroundColor(.gray)
                                                    .font(.caption)
                                            }
                                        }
                                        .padding()
                                        .background(
                                            currentSong?.id == song.id
                                            ? Color.green.opacity(0.16)
                                            : Color.white.opacity(0.06)
                                        )
                                        .cornerRadius(16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // MARK: - BLE Message / Debug Status
                        if !bleManager.lastReceivedMessage.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Device Message")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Text(bleManager.lastReceivedMessage)
                                    .foregroundColor(.green)
                                    .font(.subheadline)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            loadLibrary()
        }
    }
    
    // MARK: - Computed UI State
    
    var canControlPlayback: Bool {
        currentSong != nil && currentStem != nil
    }
    
    var homePlayButtonColor: Color {
        if !canControlPlayback { return .gray }
        return isPlaying ? .purple : .green
    }
    
    var nowPlayingGradient: LinearGradient {
        if isPlaying {
            return LinearGradient(
                colors: [Color.purple.opacity(0.85), Color.blue.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color.gray.opacity(0.7), Color.white.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var nowPlayingSubtitle: String {
        if let currentStem {
            return displayName(for: currentStem)
        }
        return ""
    }
    
    var homePlaybackStatus: String {
        if currentSong == nil || currentStem == nil { return "No active song" }
        return isPlaying ? "Playing" : "Paused"
    }
    
    var homePlaybackDetail: String {
        guard let song = currentSong, let stem = currentStem else {
            return "Select a song and stem from the library"
        }
        return "\(song.title) • \(displayName(for: stem))"
    }
    
    // MARK: - Actions
    
    // End-to-end demo flow:
    // 1. Download the selected stem from Lucas's backend
    // 2. Fetch the plain-text lyric lines for that song
    // 3. Update the home screen now-playing state
    // 4. Send PLAY to the ESP32
    // 5. Send lyric lines over BLE one by one at a fixed interval
    func startPlayback(song: Song, stem: StemType) {
        Task {
            await MainActor.run {
                currentSong = song
                currentStem = stem
                isPlaying = false
                uploadStatus = "Loading \(displayName(for: stem)) for \(song.title)..."
            }

            do {
                
                let url = try await api.getOrDownloadStem(songTitle: song.title, stem: stem)
                print("Stem file ready:", url)
                
                let duration = await getAudioDuration(from: url)
                print("Audio duration:", duration ?? -1)

                //let data = try Data(contentsOf: url)
                //print("Stem size:", data.count, "bytes")

                let exists = FileManager.default.fileExists(atPath: url.path)
                print("Stem exists at path?", exists)

                await MainActor.run {
                    uploadStatus = "Fetching lyrics for \(song.title)..."
                }

                let lyrics = try await api.fetchLyrics(songTitle: song.title)
                print("Fetched \(lyrics.count) lyric lines")

                for line in lyrics.prefix(5) {
                    print("Lyric line:", line)
                }

                await MainActor.run {
                    isPlaying = true
                    uploadStatus = "Now playing \(song.title) • \(displayName(for: stem))"
                }

                if bleManager.isConnected {
                    bleManager.sendCommand("PLAY")
                    await sendLyricsOverBLE(lyrics, songDurationSec: song.durationSec)                } else {
                    await MainActor.run {
                        uploadStatus = "Stem ready, but BLE is not connected"
                    }
                }

            } catch {
                await MainActor.run {
                    isPlaying = false
                    uploadStatus = "Playback setup failed: \(error.localizedDescription)"
                }
                print("Playback setup failed:", error)
            }
        }
    }
    
    func togglePlaybackFromHome() {
        guard canControlPlayback else { return }
        
        isPlaying.toggle()
        bleManager.sendCommand(isPlaying ? "PLAY" : "PAUSE")
    }
    
    // For tomorrow's demo there is not yet a real backend /library/ endpoint.
    // So refresh just stops the loading state and preserves the in-memory songs
    // that were added after successful uploads in this app session.
    func loadLibrary() {
        isLoadingLibrary = true
        
        Task {
            do {
                let songs = try await api.fetchLibrary()
                
                await MainActor.run {
                    if !songs.isEmpty {
                        librarySongs = songs
                    }
                    isLoadingLibrary = false
                }
            } catch {
                await MainActor.run {
                    uploadStatus = "Library error: \(error.localizedDescription)"
                    isLoadingLibrary = false
                }
            }
        }
    }
    
    func parseSongAndArtist(from fileName: String) -> (song: String, artist: String)? {
        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let parts = base.components(separatedBy: " - ")

        guard parts.count >= 2 else { return nil }

        let song = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

        guard !song.isEmpty, !artist.isEmpty else { return nil }
        return (song, artist)
    }

    func uploadWAV(url: URL) {
        print("uploadWAV called with:", url)
        uploadStatus = "Checking server for existing song..."

        Task {
            do {
                if let parsed = parseSongAndArtist(from: url.lastPathComponent) {
                    let exists = try await api.checkSongExists(
                        songTitle: parsed.song,
                        artist: parsed.artist
                    )

                    if exists {
                        await MainActor.run {
                            let localSong = Song(
                                id: parsed.song,
                                title: parsed.song,
                                durationSec: nil
                            )

                            librarySongs.removeAll { $0.title == localSong.title }
                            librarySongs.insert(localSong, at: 0)
                            uploadStatus = "Song already exists on server: \(parsed.song)"
                        }
                        return
                    }
                }

                await MainActor.run {
                    uploadStatus = "Uploading and processing... this may take several minutes"
                }

                let response = try await api.uploadSong(fileURL: url)

                await MainActor.run {
                    let songTitleFromServer = response.song_name?.trimmingCharacters(in: .whitespacesAndNewlines)

                    let fallbackName = url.deletingPathExtension().lastPathComponent
                        .components(separatedBy: " - ")
                        .first ?? url.deletingPathExtension().lastPathComponent

                    let finalSongTitle = (songTitleFromServer?.isEmpty == false)
                        ? songTitleFromServer!
                        : fallbackName

                    let localSong = Song(
                        id: finalSongTitle,
                        title: finalSongTitle,
                        durationSec: nil
                    )

                    librarySongs.removeAll { $0.title == localSong.title }
                    librarySongs.insert(localSong, at: 0)

                    uploadStatus = response.message ?? "Uploaded to library: \(localSong.title)"
                    print("Upload success, inserted into local library:", localSong.title)
                }

            } catch {
                await MainActor.run {
                    uploadStatus = "Error: \(error.localizedDescription)"
                }
                print("Upload error:", error.localizedDescription)
            }
        }
    }
    
    func buildLyricChunks(
        from lines: [String],
        targetWordsPerChunk: Int = 4,
        maxCharactersPerChunk: Int = 24
    ) -> [String] {
        
        let allWords = lines
            .flatMap { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(whereSeparator: { $0.isWhitespace })
                    .map(String.init)
            }
        
        guard !allWords.isEmpty else { return [] }
        
        var chunks: [String] = []
        var currentWords: [String] = []
        
        for word in allWords {
            let testWords = currentWords + [word]
            let testChunk = testWords.joined(separator: " ")
            
            // If adding this word would make the chunk too long,
            // finalize the current chunk first (if it has anything in it).
            if !currentWords.isEmpty && testChunk.count > maxCharactersPerChunk {
                chunks.append(currentWords.joined(separator: " "))
                currentWords = [word]
                continue
            }
            
            currentWords.append(word)
            
            // Prefer chunks of about 4 words, as long as they fit
            if currentWords.count >= targetWordsPerChunk {
                chunks.append(currentWords.joined(separator: " "))
                currentWords.removeAll()
            }
        }
        
        // Handle leftover words at the end
        if !currentWords.isEmpty {
            let leftover = currentWords.joined(separator: " ")
            
            if let last = chunks.last {
                let merged = last + " " + leftover
                if merged.count <= maxCharactersPerChunk {
                    chunks[chunks.count - 1] = merged
                } else {
                    chunks.append(leftover)
                }
            } else {
                chunks.append(leftover)
            }
        }
        
        return chunks
    }
    
    // Sends lyric lines to the ESP32 one at a time.
    // For tomorrow's demo we use a simple fixed delay instead of true timestamp sync.
    func sendLyricsOverBLE(_ lyrics: [String], songDurationSec: Double?) async {
        let lyricChunks = buildLyricChunks(
            from: lyrics,
            targetWordsPerChunk: 4,
            maxCharactersPerChunk: 24
        )
        
        guard !lyricChunks.isEmpty else {
            await MainActor.run {
                uploadStatus = "No lyric chunks to send"
            }
            return
        }
        
        print("Total lyric lines fetched:", lyrics.count)
        print("Total lyric chunks built:", lyricChunks.count)
        
        for (index, chunk) in lyricChunks.enumerated() {
            print("Chunk \(index + 1): \(chunk)")
        }
        
        let delayPerChunkSec: Double
        if let duration = songDurationSec, duration > 0 {
            delayPerChunkSec = max(1.0, duration / Double(lyricChunks.count))
        } else {
            delayPerChunkSec = 2.0
        }
        
        print("Delay per chunk:", delayPerChunkSec, "seconds")
        
        for (index, chunk) in lyricChunks.enumerated() {
            if Task.isCancelled { return }
            
            let cleanChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanChunk.isEmpty else { continue }
            
            let message = "LYRIC:\(cleanChunk)"
            print("Sending lyric chunk \(index + 1)/\(lyricChunks.count):", message)
            bleManager.sendCommand(message)
            
            await MainActor.run {
                uploadStatus = "Sending lyric \(index + 1)/\(lyricChunks.count): \(cleanChunk)"
            }
            
            let delayNs = UInt64(delayPerChunkSec * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNs)
        }
        
        await MainActor.run {
            if let song = currentSong, let stem = currentStem {
                uploadStatus = "Lyric send complete for \(song.title) • \(displayName(for: stem))"
            } else {
                uploadStatus = "Lyric send complete"
            }
        }
    }
    
    func getAudioDuration(from url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)

        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)

            if seconds.isFinite {
                return seconds
            }
        } catch {
            print("Failed to load duration:", error)
        }

        return nil
    }
    
    func displayName(for stem: StemType) -> String {
        switch stem {
        case .drums: return "Drums"
        case .bass: return "Bass"
        case .vocals: return "Vocals"
        case .other: return "Other"
        }
    }
}

struct SongDetailView: View {
    
    let song: Song
    let bleConnected: Bool
    let currentSong: Song?
    let currentStem: StemType?
    let onPlayStem: (Song, StemType) -> Void
    
    @State private var selectedStem: StemType = .drums
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // MARK: - Artwork Placeholder
                    RoundedRectangle(cornerRadius: 26)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.9), Color.blue.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 180)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(song.title)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        if let duration = song.durationSec {
                            Text(String(format: "%.0f sec", duration))
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        } else {
                            Text("Choose a stem to start playback")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // MARK: - Compact Status Row
                    HStack {
                        Text(displayName(for: selectedStem))
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text(bleConnected ? "Connected" : "Not Connected")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(bleConnected ? .green : .orange)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(16)
                    
                    // MARK: - Stem Selection
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Choose Stem")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            stemButton(.drums, icon: "dot.radiowaves.left.and.right")
                            stemButton(.bass, icon: "guitars.fill")
                            stemButton(.vocals, icon: "music.mic")
                            stemButton(.other, icon: "waveform")
                        }
                    }
                    
                    // MARK: - Play Button
                    Button(action: {
                        onPlayStem(song, selectedStem)
                        dismiss()
                    }) {
                        HStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.headline)
                            Text("Play This Stem")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background(bleConnected ? Color.green : Color.gray.opacity(0.7))
                        .cornerRadius(18)
                    }
                }
                .padding()
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Song")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
    
    @ViewBuilder
    func stemButton(_ stem: StemType, icon: String) -> some View {
        let isSelected = selectedStem == stem
        
        Button(action: {
            selectedStem = stem
        }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                
                Text(displayName(for: stem))
                    .fontWeight(.semibold)
                    .font(.subheadline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isSelected
                ? Color.green.opacity(0.9)
                : Color.white.opacity(0.08)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.green : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .cornerRadius(16)
        }
    }
    
    func displayName(for stem: StemType) -> String {
        switch stem {
        case .drums: return "Drums"
        case .bass: return "Bass"
        case .vocals: return "Vocals"
        case .other: return "Other"
        }
    }
    
}

#Preview {
    ContentView()
        .environmentObject(BLEManager())
}
