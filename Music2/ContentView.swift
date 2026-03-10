//
//  ContentView.swift
//  Music2
//
//  Created by grace keywork on 2/16/26.
//

import SwiftUI
import UniformTypeIdentifiers

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
                                        
                                        if let currentStem {
                                            Text("Stem: \(displayName(for: currentStem))")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                
                                HStack(spacing: 16) {
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
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(homePlaybackStatus)
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                        
                                        Text(homePlaybackDetail)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    
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
                        
                        // MARK: - Dev/Test Button
                        Button("Test Pipeline (No Server)") {
                            runMockPipelineTest()
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                        .padding(.top, 8)
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
    
    /*
    var canControlPlayback: Bool {
        bleManager.isConnected && currentSong != nil && currentStem != nil
    }
    */
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
            return isPlaying ? "Playing \(displayName(for: currentStem)) stem" : "Ready to resume"
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
    
    func startPlayback(song: Song, stem: StemType) {
        currentSong = song
        currentStem = stem
        isPlaying = true
        
        if bleManager.isConnected {
            bleManager.sendCommand("PLAY")
        }
        
        uploadStatus = "Now playing \(song.title) • \(displayName(for: stem))"
    }
    
    func togglePlaybackFromHome() {
        guard canControlPlayback else { return }
        
        isPlaying.toggle()
        bleManager.sendCommand(isPlaying ? "PLAY" : "PAUSE")
    }
    
    func loadLibrary() {
        isLoadingLibrary = true
        
        Task {
            do {
                let songs = try await api.fetchLibrary()
                
                await MainActor.run {
                    librarySongs = songs
                    
                    if let currentSong,
                       !songs.contains(where: { $0.id == currentSong.id }) {
                        self.currentSong = nil
                        self.currentStem = nil
                        isPlaying = false
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
    
    func uploadWAV(url: URL) {
        uploadStatus = "Uploading..."
        
        Task {
            do {
                _ = try await api.uploadSong(fileURL: url)
                
                await MainActor.run {
                    let localSong = Song(
                        id: UUID().uuidString,
                        title: url.deletingPathExtension().lastPathComponent,
                        durationSec: nil
                    )
                    
                    librarySongs.insert(localSong, at: 0)
                    uploadStatus = "Uploaded to library: \(localSong.title)"
                }
            } catch {
                await MainActor.run {
                    uploadStatus = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func runMockPipelineTest() {
        Task {
            do {
                let songs = try await api.fetchLibrary()
                guard let song = songs.first else {
                    await MainActor.run {
                        uploadStatus = "No mock songs"
                    }
                    return
                }
                
                let format = AudioFormat(
                    sampleRate: 48000,
                    channels: 1,
                    bitsPerSample: 16,
                    chunkDurationSec: 5
                )
                
                let chunk0 = try await api.fetchStemChunk(songID: song.id, stem: .drums, chunkIndex: 0, format: format)
                let chunk1 = try await api.fetchStemChunk(songID: song.id, stem: .drums, chunkIndex: 1, format: format)
                let chunk2 = try await api.fetchStemChunk(songID: song.id, stem: .drums, chunkIndex: 2, format: format)
                
                let savedURL = try TempStorage.writeChunk(
                    songID: song.id,
                    stem: .drums,
                    chunkIndex: 0,
                    data: chunk0,
                    ext: "pcm"
                )
                
                let lyrics = try await api.fetchLyrics(songID: song.id)
                
                await MainActor.run {
                    uploadStatus = """
                    Mock OK
                    chunk0 bytes: \(chunk0.count)
                    chunk1 bytes: \(chunk1.count)
                    chunk2 bytes: \(chunk2.count)
                    saved: \(savedURL.lastPathComponent)
                    lyrics lines: \(lyrics.count)
                    """
                }
                
                print("Saved chunk at:", savedURL)
            } catch {
                await MainActor.run {
                    uploadStatus = "Test error: \(error.localizedDescription)"
                }
            }
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
                    /*
                    if currentSong?.id == song.id, let currentStem {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Current Active Stem")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Text(displayName(for: currentStem))
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(14)
                    }
                     */
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
