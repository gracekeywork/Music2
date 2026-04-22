//
//  ContentView.swift
//  Music2
//
//  Created by grace keywork on 2/16/26.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

extension Color {
    static let ravenBlack = Color(red: 28/255, green: 18/255, blue: 8/255)       // #1C1208
    static let darkChestnut = Color(red: 92/255, green: 42/255, blue: 14/255)    // #5C2A0E
    static let burntSienna = Color(red: 160/255, green: 68/255, blue: 15/255)    // #A0440F
    static let copperRust = Color(red: 196/255, green: 98/255, blue: 26/255)     // #C4621A
    static let warmAmber = Color(red: 217/255, green: 139/255, blue: 46/255)     // #D98B2E
    static let goldenBuff = Color(red: 232/255, green: 181/255, blue: 90/255)    // #E8B55A
    static let paleOchre = Color(red: 232/255, green: 201/255, blue: 138/255)    // #E8C98A
    static let birchCream = Color(red: 242/255, green: 229/255, blue: 196/255)   // #F2E5C4
}

struct ContentView: View {
    
    @EnvironmentObject var bleManager: BLEManager
    private let api = ServerAPI()
    
    // Current now-playing state for home screen
    @State private var currentSong: Song? = nil
    //Starting with drums as a default
    @State private var selectedStem1: StemType = .drums
    @State private var selectedStem2: StemChoice = .none

    @State private var stemLevel1: Double = 0.5
    @State private var stemLevel2: Double = 0.5
    //@State private var currentStem: StemType? = nil
    @State private var isPlaying = false
    @State private var songAdvanceTask: Task<Void, Never>? = nil
    @State private var currentSongDuration: Double? = nil
    
    // Library / upload state
    @State private var librarySongs: [Song] = []
    @State private var showFilePicker = false
    @State private var uploadStatus = ""
    @State private var isLoadingLibrary = false
    
    // Lyric sending state
    @State private var currentLyricChunks: [String] = []
    @State private var currentLyricChunkIndex: Int = 0
    @State private var lyricSendTask: Task<Void, Never>? = nil
    
    @State private var isPlaybackSettingsExpanded = false
       
    // Prevent handling the same incoming BLE notification repeatedly
    @State private var lastHandledBLEMessage: String = ""
    
    @State private var lastAppliedPlaybackSettings: PlaybackSettingsRequest? = nil
    
    @State private var backPressCount: Int = 0
    @State private var backPressResetTask: Task<Void, Never>? = nil
    
    @State private var currentAudioPackets: [Data] = []
    @State private var currentPacketIndex: Int = 0
    @State private var audioPacketSendTask: Task<Void, Never>? = nil
    
    @State private var lyricPlaybackStartTime: Date? = nil
    @State private var lyricElapsedBeforePause: Double = 0
    @State private var songAdvanceElapsedBeforePause: Double = 0
    
    
    
    var activeStem1: StemType {
        selectedStem1
    }

    var activeStem2: StemType? {
        selectedStem2.asStemType
    }
    
    var activeStemDisplayText: String {
        if let stem2 = activeStem2 {
            return "\(displayName(for: activeStem1)) + \(displayName(for: stem2))"
        } else {
            return displayName(for: activeStem1)
        }
    }
    var requestedStems: [StemType] {
        var stems: [StemType] = [selectedStem1]

        if let stem2 = selectedStem2.asStemType, stem2 != selectedStem1 {
            stems.append(stem2)
        }

        return stems
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Color.ravenBlack.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // MARK: - Header
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Music2")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.burntSienna)
                                
                                Text("Haptic music experience")
                                    .font(.subheadline)
                                    .foregroundColor(.paleOchre)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(bleManager.isConnected ? Color.green : Color.red)
                                    .frame(width: 10, height: 10)
                                
                                Text(bleManager.isConnected ? "Connected" : "Scanning...")
                                    .font(.caption)
                                    .foregroundColor(.birchCream)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.darkChestnut.opacity(0.9))
                            .cornerRadius(12)
                        }
                    
                        // MARK: - Global Playback Settings
                        VStack(alignment: .leading, spacing: 16) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isPlaybackSettingsExpanded.toggle()
                                }
                            }) {
                                HStack {
                                    Text("Playback Settings")
                                        .font(.headline)
                                        .foregroundColor(.birchCream)

                                    Spacer()

                                    Image(systemName: isPlaybackSettingsExpanded ? "chevron.up" : "chevron.down")
                                        .foregroundColor(.birchCream)
                                }
                            }
                            .buttonStyle(.plain)

                            if isPlaybackSettingsExpanded {
                                VStack(alignment: .leading, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Stem 1")
                                            .foregroundColor(.birchCream)

                                        Picker("Stem 1", selection: $selectedStem1) {
                                            Text("Drums").tag(StemType.drums)
                                            Text("Bass").tag(StemType.bass)
                                            Text("Vocals").tag(StemType.vocals)
                                            Text("Other").tag(StemType.other)
                                        }
                                        .pickerStyle(.segmented)

                                        HStack {
                                            Text("Level")
                                                .foregroundColor(.birchCream)
                                            Spacer()
                                            Text("\(Int(stemLevel1 * 100))%")
                                                .foregroundColor(.gray)
                                        }

                                        Slider(value: $stemLevel1, in: 0...1)
                                            .tint(.warmAmber)
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Stem 2")
                                            .foregroundColor(.birchCream)

                                        Picker("Stem 2", selection: $selectedStem2) {
                                            Text("None").tag(StemChoice.none)
                                            Text("Drums").tag(StemChoice.drums)
                                            Text("Bass").tag(StemChoice.bass)
                                            Text("Vocals").tag(StemChoice.vocals)
                                            Text("Other").tag(StemChoice.other)
                                        }
                                        .pickerStyle(.segmented)

                                        HStack {
                                            Text("Level")
                                                .foregroundColor(.birchCream)
                                            Spacer()
                                            Text("\(Int(stemLevel2 * 100))%")
                                                .foregroundColor(.gray)
                                        }

                                        Slider(value: $stemLevel2, in: 0...1)
                                            .disabled(selectedStem2 == .none)
                                            .opacity(selectedStem2 == .none ? 0.4 : 1.0)
                                            .tint(.warmAmber)
                                    }

                                    Button(action: {
                                        applyPlaybackSettings()
                                    }) {
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                            Text("Confirm Playback Settings")
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundColor(.birchCream)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(currentSong == nil ? Color.darkChestnut : Color.copperRust)
                                        .cornerRadius(14)
                                    }
                                    .disabled(currentSong == nil)
                                    .opacity(currentSong == nil ? 0.5 : 1.0)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding()
                        .background(Color.burntSienna.opacity(0.30))
                        .cornerRadius(16)
                        

                        
                        
                        // MARK: - Now Playing Card
                        if currentSong != nil  {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Now Playing")
                                    .font(.headline)
                                    .foregroundColor(.birchCream)
                                
                                HStack(spacing: 16) {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(nowPlayingGradient)
                                        .frame(width: 90, height: 90)
                                        .overlay(
                                            Image(systemName: "waveform")
                                                .font(.system(size: 30))
                                                .foregroundColor(.birchCream)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(currentSong?.title ?? "")
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.birchCream)
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
                                            .foregroundColor(.birchCream)
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
                            .background(Color.darkChestnut.opacity(0.85))
                            .cornerRadius(20)
                        }
                        
                        // MARK: - Library Header
                        HStack {
                            Text("Library")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.paleOchre)
                            
                            Spacer()
                            
                            Button(action: {
                                loadLibrary()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Refresh")
                                }
                                .font(.caption)
                                .foregroundColor(.birchCream)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.birchCream.opacity(0.08))
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
                            .foregroundColor(.ravenBlack)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.warmAmber)
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
                                .foregroundColor(.birchCream)
                                .font(.subheadline)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.warmAmber.opacity(0.9))
                                .cornerRadius(12)
                        }
                        
                        // MARK: - Library List
                        if isLoadingLibrary {
                            ProgressView()
                                .tint(.birchCream)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical)
                        } else if librarySongs.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No songs in library yet")
                                    .foregroundColor(.birchCream)
                                    .font(.headline)
                                
                                Text("Upload a song or refresh the library to load available tracks.")
                                    .foregroundColor(.paleOchre)
                                    .font(.subheadline)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.burntSienna.opacity(0.85))
                            .cornerRadius(16)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(librarySongs) { song in
                                    Button {
                                        startPlayback(song: song)
                                    } label: {
                                        HStack(spacing: 14) {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.burntSienna.opacity(0.45))
                                                .frame(width: 56, height: 56)
                                                .overlay(
                                                    Image(systemName: "music.note")
                                                        .foregroundColor(.paleOchre)
                                                )

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(song.title)
                                                    .foregroundColor(.birchCream)
                                                    .font(.headline)
                                                    .multilineTextAlignment(.leading)

                                                if let duration = song.durationSec {
                                                    Text(String(format: "%.0f sec", duration))
                                                        .foregroundColor(.gray)
                                                        .font(.caption)
                                                } else {
                                                    Text("Tap to play from here")
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
                                            ? Color.warmAmber.opacity(0.22)
                                            : Color.darkChestnut.opacity(0.82)
                                        )
                                        .cornerRadius(16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // MARK: - BLE Message / Debug Status
                        /*
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
                        }*/
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            loadLibrary()
        }
        .onChange(of: bleManager.messageEventID) {
            handleIncomingBLEMessage(bleManager.lastReceivedMessage)
        }
        .onChange(of: selectedStem1) {
            if selectedStem2.asStemType == selectedStem1 {
                selectedStem2 = .none
            }
        }
        .onChange(of: selectedStem2) {
            if selectedStem2.asStemType == selectedStem1 {
                selectedStem2 = .none
            }
        }
    }
    
    // MARK: - Computed UI State
    
    var canControlPlayback: Bool {
        currentSong != nil
    }
    
    var homePlayButtonColor: Color {
        if !canControlPlayback { return .darkChestnut }
        return isPlaying ? .copperRust : .warmAmber
    }
    
    var nowPlayingGradient: LinearGradient {
        if isPlaying {
            return LinearGradient(
                colors: [Color.purple.opacity(0.85), Color.copperRust.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color.gray.opacity(0.7), Color.birchCream.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var nowPlayingSubtitle: String {
        activeStemDisplayText
    }
    
    var homePlaybackStatus: String {
        if currentSong == nil { return "No active song" }
        return isPlaying ? "Playing" : "Paused"
    }

    var homePlaybackDetail: String {
        guard let song = currentSong else {
            return "Select a song from the library"
        }
        return "\(song.title) • \(activeStemDisplayText)"
    }
    
    func playNextSongInLibrary() {
        guard let current = currentSong,
              let currentIndex = librarySongs.firstIndex(where: { $0.id == current.id }) else {
            isPlaying = false
            songAdvanceTask?.cancel()
            songAdvanceTask = nil
            uploadStatus = "No current song"
            return
        }

        let nextIndex = currentIndex + 1

        guard nextIndex < librarySongs.count else {
            isPlaying = false
            songAdvanceTask?.cancel()
            songAdvanceTask = nil
            uploadStatus = "Reached end of library"
            return
        }

        let nextSong = librarySongs[nextIndex]
        startPlayback(song: nextSong)
    }
    
    func parseTimedLyricLines(from lines: [String]) -> [TimedLyricLine] {
        var timedLines: [TimedLyricLine] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            // Normal timestamped line
            if line.hasPrefix("["),
               let closingBracketIndex = line.firstIndex(of: "]") {

                let timeString = String(line[line.index(after: line.startIndex)..<closingBracketIndex])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let lyricText = String(line[line.index(after: closingBracketIndex)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !lyricText.isEmpty else { continue }

                let timeSec: Double?

                if timeString.contains(":") {
                    let parts = timeString.split(separator: ":").map(String.init)
                    if parts.count == 2,
                       let minutes = Double(parts[0]),
                       let seconds = Double(parts[1]) {
                        timeSec = minutes * 60 + seconds
                    } else {
                        timeSec = nil
                    }
                } else {
                    timeSec = Double(timeString)
                }

                guard let parsedTime = timeSec else { continue }

                timedLines.append(TimedLyricLine(timeSec: parsedTime, text: lyricText))
            } else {
                // Continuation line with no timestamp:
                // attach it to the previous lyric instead of dropping it
                guard !timedLines.isEmpty else { continue }

                let continuation = line.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
                guard !continuation.isEmpty else { continue }

                let last = timedLines.removeLast()
                let mergedText = last.text + ", " + continuation
                timedLines.append(TimedLyricLine(timeSec: last.timeSec, text: mergedText))

                print("Merged untimestamped continuation into previous lyric:", mergedText)
            }
        }

        return timedLines.sorted { $0.timeSec < $1.timeSec }
    }
    
    /*
    func makeFourWordChunks(_ text: String) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        
        var chunks: [String] = []
        var current: [String] = []
        
        for word in words {
            current.append(word)
            
            if current.count == 4 {
                chunks.append(current.joined(separator: " "))
                current.removeAll()
            }
        }
        
        // handle leftover words
        if !current.isEmpty {
            if current.count == 1, var last = chunks.last {
                last += " " + current[0]
                chunks[chunks.count - 1] = last
            } else {
                chunks.append(current.joined(separator: " "))
            }
        }
        
        return chunks
    }
     */
    func makeDisplaySafeChunks(_ text: String, maxCharactersPerChunk: Int = 12) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        var chunks: [String] = []
        var currentChunk = ""

        for word in words {
            let candidate = currentChunk.isEmpty ? word : currentChunk + " " + word

            if candidate.count <= maxCharactersPerChunk {
                currentChunk = candidate
            } else {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                }

                currentChunk = word
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }
    
    
    // MARK: - Actions
    
    // End-to-end demo flow:
    // 1. Download the selected stem from Lucas's backend
    // 2. Fetch the plain-text lyric lines for that song
    // 3. Update the home screen now-playing state
    // 4. Send PLAY to the ESP32
    // 5. Send lyric lines over BLE one by one at a fixed interval
    func startPlayback(song: Song) {
        lyricSendTask?.cancel()
        lyricSendTask = nil
        songAdvanceTask?.cancel()
        songAdvanceTask = nil
        audioPacketSendTask?.cancel()
        audioPacketSendTask = nil
        
        //if bleManager.isConnected {
          //      bleManager.sendCommand("CLEAR")
           // }
        print("selectedStem1 at playback start:", selectedStem1)
        print("selectedStem2 at playback start:", selectedStem2)
        print("requestedStems at playback start:", requestedStems)

        let stemsToLoad = requestedStems
        let stemsLabel = stemsToLoad.map { displayName(for: $0) }.joined(separator: " + ")

        Task {
            await MainActor.run {
                currentSong = song
                isPlaying = false
                currentLyricChunks = []
                currentLyricChunkIndex = 0
                currentAudioPackets = []
                currentPacketIndex = 0
                currentSongDuration = nil
                lyricElapsedBeforePause = 0
                songAdvanceElapsedBeforePause = 0
                lyricPlaybackStartTime = nil
                uploadStatus = "Loading \(stemsLabel) for \(song.title)..."
                bleManager.audioBackpressureCount = 0
            }

            do {
                var stemURLs: [StemType: URL] = [:]

                for stem in stemsToLoad {
                    let url = try await api.getOrDownloadStem(songTitle: song.title, stem: stem)
                    stemURLs[stem] = url
                    print("Stem file ready for \(displayName(for: stem)):", url)
                }

                let primaryStem = stemsToLoad[0]

                let duration: Double?
                if let serverDuration = song.durationSec {
                    duration = serverDuration
                } else {
                    duration = await getAudioDuration(from: stemURLs[primaryStem]!)
                }

                await MainActor.run {
                    currentSongDuration = duration
                    uploadStatus = "Fetching lyrics for \(song.title)..."
                }

                let lyrics = try await api.fetchLyrics(songTitle: song.title)
                
                // ── BUILD AUDIO PACKETS (NEW PIPELINE) ──

                let monoSamplesList: [StemType: [Int16]] = try stemURLs.mapValues { url in
                    try AudioChunkLoader.loadPCM16MonoSamples(from: url)
                }

                let stereoData: Data

                if stemsToLoad.count == 1 {
                    let mono = monoSamplesList[stemsToLoad[0]]!
                    stereoData = AudioChunkLoader.makeStereoPCMDataDuplicatingMono(mono)
                } else if stemsToLoad.count >= 2 {
                    let leftSamples = monoSamplesList[stemsToLoad[0]]!
                    let rightSamples = monoSamplesList[stemsToLoad[1]]!

                    stereoData = AudioChunkLoader.makeStereoPCMData(
                        left: leftSamples,
                        right: rightSamples
                    )
                } else {
                    throw NSError(
                        domain: "Audio",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "No stems loaded"]
                    )
                }

                // Split into BLE packets (160 bytes = 5ms @ 8kHz stereo)
                let audioPackets = AudioChunkLoader.splitIntoChunks(stereoData, chunkSize: 160)
                
                /*
                let audioPackets = try await api.fetchPacketizedAudio(
                    songTitle: song.title,
                    stems: stemsToLoad
                )
                 */
                let lyricChunks = lyrics

                await MainActor.run {
                    currentLyricChunks = lyricChunks
                    currentLyricChunkIndex = 0
                    currentAudioPackets = audioPackets
                    currentPacketIndex = 0
                    isPlaying = true
                    uploadStatus = "Now playing \(song.title) • \(stemsLabel)"
                }

                await MainActor.run {
                    lyricPlaybackStartTime = Date()
                }
                if bleManager.isConnected {
                    bleManager.sendCommand("PLAY")
                    startAudioPacketSendingLoop(packetIntervalSec: 0.005)
                    startLyricSendingLoop(songDurationSec: duration)

                    if let duration, duration > 0 {
                        songAdvanceTask = Task {
                            do {
                                try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                            } catch {
                                return
                            }

                            if Task.isCancelled { return }

                            await MainActor.run {
                                guard isPlaying, currentSong?.id == song.id else { return }
                                playNextSongInLibrary()
                            }
                        }
                    }
                } else {
                    await MainActor.run {
                        uploadStatus = "Stems ready, but BLE is not connected"
                    }
                }

            } catch {
                await MainActor.run {
                    isPlaying = false
                    uploadStatus = "Playback failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func restartCurrentSong() {
        guard let song = currentSong else {
            uploadStatus = "No current song to restart"
            return
        }

        uploadStatus = "Restarting \(song.title)"
        startPlayback(song: song)
    }
    
    func playPreviousSongInLibrary() {
        guard let current = currentSong,
              let currentIndex = librarySongs.firstIndex(where: { $0.id == current.id }) else {
            uploadStatus = "No current song"
            return
        }

        guard currentIndex > 0 else {
            restartCurrentSong()
            return
        }

        let previousSong = librarySongs[currentIndex - 1]
        startPlayback(song: previousSong)
    }
    
    func handleBackButtonPressed() {
        guard currentSong != nil else {
            uploadStatus = "No current song"
            return
        }

        backPressCount += 1
        print("Back button pressed. Count =", backPressCount)

        if backPressCount == 1 {
            restartCurrentSong()
        } else if backPressCount >= 2 {
            backPressResetTask?.cancel()
            backPressResetTask = nil
            backPressCount = 0
            playPreviousSongInLibrary()
            return
        }

        backPressResetTask?.cancel()
        backPressResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second window

            if Task.isCancelled { return }

            await MainActor.run {
                self.backPressCount = 0
                self.backPressResetTask = nil
            }
        }
    }
    /*
    func applyPlaybackSettings() {
        print("Applying settings:")
        print("Stem 1:", selectedStem1)
        print("Stem 2:", selectedStem2)
        print("Requested stems:", requestedStems)
        
        guard let song = currentSong else {
            uploadStatus = "Select a song first"
            return
        }

        uploadStatus = "Applying new playback settings..."
        startPlayback(song: song)
    }
     */
    
    func applyPlaybackSettings() {
        guard let song = currentSong else {
            uploadStatus = "Select a song first"
            print("No current song - cannot apply playback settings")
            return
        }

        let stems = buildPlaybackStemEntries()
        let payload = PlaybackSettingsRequest(song: song.title, stems: stems)

        lastAppliedPlaybackSettings = payload

        print("Applying playback settings for:", song.title)
        for entry in stems {
            print("- \(entry.name): \(entry.intensity)%")
        }

        do {
            let encoded = try JSONEncoder().encode(payload)
            if let jsonString = String(data: encoded, encoding: .utf8) {
                print("Prepared playback settings JSON:")
                print(jsonString)
            }
        } catch {
            print("Failed to encode playback settings:", error.localizedDescription)
        }

        uploadStatus = "Playback settings saved for \(song.title)"

        // Optional: restart playback immediately so the new stem choices apply in-app
        startPlayback(song: song)
    }
    
    func buildPlaybackStemEntries() -> [StemMixEntry] {
        var stems: [StemMixEntry] = []

        let stem1Percent = Int((stemLevel1 * 100).rounded())
        stems.append(
            StemMixEntry(
                name: selectedStem1.rawValue,
                intensity: stem1Percent
            )
        )

        if let stem2 = selectedStem2.asStemType, stem2 != selectedStem1 {
            let stem2Percent = Int((stemLevel2 * 100).rounded())
            stems.append(
                StemMixEntry(
                    name: stem2.rawValue,
                    intensity: stem2Percent
                )
            )
        }

        return stems
    }
    
    /*
    func togglePlaybackFromHome() {
        guard canControlPlayback else { return }

        isPlaying.toggle()
        bleManager.sendCommand(isPlaying ? "PLAY" : "PAUSE")

        if isPlaying {
            if lyricPlaybackStartTime == nil {
                lyricPlaybackStartTime = Date()
            }
            uploadStatus = "Resumed \(currentSong?.title ?? "song")"
            startLyricSendingLoop(songDurationSec: currentSongDuration)

            if !currentAudioPackets.isEmpty {
                startAudioPacketSendingLoop(packetIntervalSec: 0.005)
            }
        } else {
            uploadStatus = "Paused \(currentSong?.title ?? "song")"
            lyricSendTask?.cancel()
            lyricSendTask = nil

            audioPacketSendTask?.cancel()
            audioPacketSendTask = nil

            songAdvanceTask?.cancel()
            songAdvanceTask = nil
        }
    }
    */
    func togglePlaybackFromHome() {
        guard canControlPlayback else { return }

        if isPlaying {
            // PAUSE
            if let start = lyricPlaybackStartTime {
                let elapsed = Date().timeIntervalSince(start)
                lyricElapsedBeforePause += elapsed
                songAdvanceElapsedBeforePause += elapsed
            }

            isPlaying = false
            lyricPlaybackStartTime = nil

            bleManager.sendCommand("PAUSE")
            uploadStatus = "Paused \(currentSong?.title ?? "song")"

            lyricSendTask?.cancel()
            lyricSendTask = nil

            audioPacketSendTask?.cancel()
            audioPacketSendTask = nil

            songAdvanceTask?.cancel()
            songAdvanceTask = nil
        } else {
            // RESUME
            isPlaying = true
            lyricPlaybackStartTime = Date()

            bleManager.sendCommand("PLAY")
            uploadStatus = "Resumed \(currentSong?.title ?? "song")"

            startLyricSendingLoop(songDurationSec: currentSongDuration)

            if !currentAudioPackets.isEmpty {
                startAudioPacketSendingLoop(packetIntervalSec: 0.005)
            }

            if let duration = currentSongDuration, duration > 0 {
                let remaining = max(0, duration - songAdvanceElapsedBeforePause)

                songAdvanceTask?.cancel()
                songAdvanceTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    } catch {
                        return
                    }

                    if Task.isCancelled { return }

                    await MainActor.run {
                        guard isPlaying else { return }
                        playNextSongInLibrary()
                    }
                }
            }
        }
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
                /*
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
                 */

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
    
    /*
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
    */
    
    // Sends lyric lines to the ESP32 one at a time.
    // For tomorrow's demo we use a simple fixed delay instead of true timestamp sync.
    func startLyricSendingLoop(songDurationSec: Double?) {
        lyricSendTask?.cancel()
        
        lyricSendTask = Task {
            await runLyricSendingLoop(songDurationSec: songDurationSec)
        }
    }
    
    func startAudioPacketSendingLoop(packetIntervalSec: Double) {
        audioPacketSendTask?.cancel()

        audioPacketSendTask = Task {
            await runAudioPacketSendingLoop(packetIntervalSec: packetIntervalSec)
        }
    }

    func runAudioPacketSendingLoop(packetIntervalSec: Double) async {
        guard !currentAudioPackets.isEmpty else {
            await MainActor.run {
                uploadStatus = "No audio packets to send"
            }
            return
        }

        print("Starting audio packet loop")
        print("Total packets:", currentAudioPackets.count)
        print("Packet interval:", packetIntervalSec, "seconds")

        while true {
            if Task.isCancelled { return }

            if !isPlaying {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 sec
                continue
            }

            if currentPacketIndex >= currentAudioPackets.count {
                let backpressureCount = bleManager.audioBackpressureCount

                print("BLE STABILITY | backpressure events during song: \(backpressureCount)")

                await MainActor.run {
                    if let song = currentSong {
                        uploadStatus = "Audio complete for \(song.title) • backpressure events: \(backpressureCount)"
                    } else {
                        uploadStatus = "Audio complete • backpressure events: \(backpressureCount)"
                    }
                }
                return
            }

            let packet = currentAudioPackets[currentPacketIndex]
            bleManager.sendAudioPacket(packet)

            let sentNumber = currentPacketIndex + 1
            await MainActor.run {
                uploadStatus = "Sending audio packet \(sentNumber)/\(currentAudioPackets.count)"
            }

            currentPacketIndex += 1

            let delayNs = UInt64(packetIntervalSec * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNs)
        }
    }
    
    func runLyricSendingLoop(songDurationSec: Double?) async {
        let timedLines = parseTimedLyricLines(from: currentLyricChunks)

        guard !timedLines.isEmpty else {
            await MainActor.run {
                uploadStatus = "No timestamped lyric lines to send"
            }
            return
        }

        let baseElapsed = lyricElapsedBeforePause
        let playbackStart = lyricPlaybackStartTime ?? Date()

        let tolerance = 0.4
        let startIndex = timedLines.firstIndex(where: {
            $0.timeSec >= (baseElapsed - tolerance)
        }) ?? timedLines.count

        for index in startIndex..<timedLines.count {
            if Task.isCancelled { return }

            let timedLine = timedLines[index]

            while !isPlaying {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            let elapsed = baseElapsed + Date().timeIntervalSince(playbackStart)
            let delayUntilLine = timedLine.timeSec - elapsed

            if delayUntilLine > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delayUntilLine * 1_000_000_000))
            }

            if Task.isCancelled { return }

            while !isPlaying {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            print("Sending timed lyric line \(index + 1)/\(timedLines.count): [\(timedLine.timeSec)] \(timedLine.text)")
            let actualElapsed = baseElapsed + Date().timeIntervalSince(playbackStart)
            let timingError = actualElapsed - timedLine.timeSec

            print(
                String(
                    format: "LYRIC TIMING | target: %.3f s | actual: %.3f s | error: %.3f s | text: %@",
                    timedLine.timeSec,
                    actualElapsed,
                    timingError,
                    timedLine.text
                )
            )

            let chunks = makeDisplaySafeChunks(timedLine.text, maxCharactersPerChunk: 12)

            let nextTime = (index + 1 < timedLines.count)
                ? timedLines[index + 1].timeSec
                : timedLine.timeSec + 3.0

            let buffer: Double = 0.3
            let available = max(0.2, nextTime - timedLine.timeSec - buffer)
            let spacing = available / Double(max(chunks.count, 1))

            for (chunkIndex, chunk) in chunks.enumerated() {
                if Task.isCancelled { return }

                let targetTime = timedLine.timeSec + Double(chunkIndex) * spacing
                let nowElapsed = baseElapsed + Date().timeIntervalSince(playbackStart)
                let delay = targetTime - nowElapsed

                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                if Task.isCancelled { return }

                while !isPlaying {
                    if Task.isCancelled { return }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }

                print("SENDING CHUNK:", chunk)
                bleManager.sendCommand("LYRIC:\(chunk)")

                await MainActor.run {
                    uploadStatus = "Lyric: \(chunk)"
                }
            }

            print("SENDING TO ESP32:", "LYRIC:\(timedLine.text)")

            await MainActor.run {
                currentLyricChunkIndex = index + 1
                uploadStatus = "Sending lyric: \(timedLine.text)"
            }
        }

        await MainActor.run {
            if let song = currentSong {
                uploadStatus = "Lyric send complete for \(song.title) • \(activeStemDisplayText)"
            } else {
                uploadStatus = "Lyric send complete"
            }
        }
    }
    /*
    func runLyricSendingLoop(songDurationSec: Double?) async {
        guard !currentLyricChunks.isEmpty else {
            await MainActor.run {
                uploadStatus = "No lyric chunks to send"
            }
            return
        }
        
        let delayPerChunkSec: Double
        if let duration = songDurationSec, duration > 0 {
            delayPerChunkSec = max(1.0, duration / Double(max(currentLyricChunks.count, 1)))
        } else {
            delayPerChunkSec = 2.0
        }
        
        print("Delay per chunk:", delayPerChunkSec, "seconds")
        
        while true {
            if Task.isCancelled { return }
            
            if !isPlaying {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 sec
                continue
            }
            
            if currentLyricChunkIndex >= currentLyricChunks.count {
                await MainActor.run {
                    if let song = currentSong {
                        uploadStatus = "Lyric send complete for \(song.title) • \(activeStemDisplayText)"
                    } else {
                        uploadStatus = "Lyric send complete"
                    }
                }
                return
            }
            
            let chunk = currentLyricChunks[currentLyricChunkIndex]
            let cleanChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !cleanChunk.isEmpty {
                print("Sending lyric line \(currentLyricChunkIndex + 1)/\(currentLyricChunks.count):", cleanChunk)
                bleManager.sendCommand(cleanChunk)
                
                await MainActor.run {
                    uploadStatus = "Sending lyric: \(cleanChunk)"
                }
            }
            
            currentLyricChunkIndex += 1
            
            let delayNs = UInt64(delayPerChunkSec * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNs)
        }
    }
    */
    
    func handleIncomingBLEMessage(_ message: String) {
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else { return }

        print("Handling incoming BLE message:", cleanMessage)

        if cleanMessage == "PAUSE" {
            guard canControlPlayback else { return }

            DispatchQueue.main.async {
                guard self.isPlaying else { return }

                if let start = self.lyricPlaybackStartTime {
                    let elapsed = Date().timeIntervalSince(start)
                    self.lyricElapsedBeforePause += elapsed
                    self.songAdvanceElapsedBeforePause += elapsed
                }

                self.isPlaying = false
                self.lyricPlaybackStartTime = nil
                self.uploadStatus = "Paused from touch control"

                self.lyricSendTask?.cancel()
                self.lyricSendTask = nil

                self.audioPacketSendTask?.cancel()
                self.audioPacketSendTask = nil

                self.songAdvanceTask?.cancel()
                self.songAdvanceTask = nil
            }
            return
        }

        if cleanMessage == "PLAY" {
            guard canControlPlayback else { return }

            DispatchQueue.main.async {
                guard !self.isPlaying else { return }

                self.isPlaying = true
                self.lyricPlaybackStartTime = Date()
                self.uploadStatus = "Resumed from touch control"

                self.startLyricSendingLoop(songDurationSec: self.currentSongDuration)

                if !self.currentAudioPackets.isEmpty {
                    self.startAudioPacketSendingLoop(packetIntervalSec: 0.005)
                }

                if let duration = self.currentSongDuration, duration > 0 {
                    let remaining = max(0, duration - self.songAdvanceElapsedBeforePause)

                    self.songAdvanceTask?.cancel()
                    self.songAdvanceTask = Task {
                        do {
                            try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                        } catch {
                            return
                        }

                        if Task.isCancelled { return }

                        await MainActor.run {
                            guard self.isPlaying else { return }
                            self.playNextSongInLibrary()
                        }
                    }
                }
            }
            return
        }

        if cleanMessage == "SKIP_NEXT" {
            guard canControlPlayback else { return }

            DispatchQueue.main.async {
                self.uploadStatus = "Skipping to next song"
                self.playNextSongInLibrary()
            }
            return
        }

        if cleanMessage == "SKIP_PREV" {
            guard canControlPlayback else { return }

            DispatchQueue.main.async {
                self.handleBackButtonPressed()
            }
            return
        }

        if cleanMessage == "TOUCH0_OFF" || cleanMessage == "TOUCH1_OFF" || cleanMessage == "TOUCH2_OFF" {
            print("Ignoring touch OFF message:", cleanMessage)
            return
        }

        guard cleanMessage != lastHandledBLEMessage else { return }
        lastHandledBLEMessage = cleanMessage
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
struct TimedLyricLine {
    let timeSec: Double
    let text: String
}

/*
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
*/

#Preview {
    ContentView()
        .environmentObject(BLEManager())
}
