//
//  Models.swift
//  Music2
//
//  Created by grace keywork on 3/2/26.
//

import Foundation   // Basic Swift types like UUID, Codable, etc.

// ── STEM TYPE ─────────────────────────────────────────────────────────────────
// The 4 music stems that Demucs (Lucas's ML model) will separate every song into
// String - means each case has a string value equal to its name (e.g. .drums = "drums")
//          useful when building URL paths like /stems/song123/drums/0
// CaseIterable - means we can loop over all 4 cases with StemType.allCases
//                will be useful later for building intensity sliders for each stem
// Codable - means it can be converted to/from JSON automatically
//           needed if Lucas ever sends stem info as part of a JSON response
enum StemType: String, CaseIterable, Codable {
    case drums
    case bass
    case vocals
    case other
}

// ── SONG ──────────────────────────────────────────────────────────────────────
// Represents one song in the library
// Identifiable - means SwiftUI can use this directly in Lists without extra code
//                requires an 'id' field, which we have
// Codable - means it can be decoded directly from Lucas's JSON response
//           e.g. {"id": "abc123", "title": "My Song", "durationSec": 210.5}
struct Song: Identifiable, Codable {
    let id: String          // unique song identifier assigned by Lucas's server
    let title: String       // display name shown in the app UI
    let durationSec: Double? // total song length - optional because Lucas might not always send it
}

// ── AUDIO FORMAT ──────────────────────────────────────────────────────────────
// Defines the exact technical format of the audio chunks we expect from Lucas
// This is the agreement between us and Lucas - if he sends different numbers
// the audio will sound wrong or broken when played through the transducers
// Codable - included in case we ever send or receive this as JSON
struct AudioFormat: Codable {
    let sampleRate: Int         // samples per second - we use 16000 Hz
                                // Lucas must output stems at this exact rate
    let channels: Int           // 1 = mono (one audio channel)
                                // we use mono since transducers don't need stereo
    let bitsPerSample: Int      // bit depth - we use 16-bit
                                // determines audio quality and file size
    let chunkDurationSec: Int   // how many seconds of audio per chunk - we use 5
                                // app requests next chunk when buffer runs low
}

// ── LYRIC LINE ────────────────────────────────────────────────────────────────
// Represents one line of lyrics with a timestamp
// Used to sync lyrics to playback and display them on Caitlyn's glasses
// Identifiable - lets SwiftUI use these in lists, requires an 'id' field
// Codable - can be decoded from Lucas's JSON response
struct LyricLine: Identifiable, Codable {
    let id = UUID()     // generated locally on the iPhone - NOT from Lucas's server
                        // just gives SwiftUI a unique ID to track each line in a list
    let timeMs: Int     // when this lyric should appear, in milliseconds from song start
                        // e.g. 4500 means show this line 4.5 seconds into the song
    let text: String    // the actual lyric text to display
                        // e.g. "Never gonna give you up"

    // CodingKeys tells Swift's JSON decoder which fields to look for in Lucas's response
    // We only list timeMs and text here - 'id' is intentionally excluded because
    // it's generated on our side and doesn't come from the server
    // Without this, the decoder would crash trying to find "id" in Lucas's JSON
    enum CodingKeys: String, CodingKey {
        case timeMs
        case text
    }
}
