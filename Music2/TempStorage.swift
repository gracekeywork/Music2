//
//  TempStorage.swift
//  Music2
//
//  Created by grace keywork on 3/2/26.
//

import Foundation

// TempStorage manages saving audio chunk data to the iPhone's temporary directory
// Think of it as a local cache - chunks arrive from Lucas's server over the network
// and get saved here so we can stream them to Caitlyn's ESP32 without re-downloading
//
// Using 'enum' with no cases is a Swift pattern for a namespace of static functions
// It means you can never accidentally do TempStorage() - it's purely a utility toolbox
//
// iOS can clear the temporary directory when it needs space, which is fine here
// because these chunks are streaming cache, not permanent storage
enum TempStorage {

    // ── FOLDER STRUCTURE ──────────────────────────────────────────────────────
    //
    // Files are organized like this on disk:
    //
    // /tmp/Music2/
    //   {songID}/
    //     drums/
    //       chunk_0000.pcm
    //       chunk_0001.pcm
    //     bass/
    //       chunk_0000.pcm
    //     vocals/
    //       chunk_0000.pcm
    //     other/
    //       chunk_0000.pcm

    // Returns the folder path for a specific song
    // e.g. /tmp/Music2/mock_song_001/
    // Does NOT create the folder - just builds the URL
    static func songDir(songID: String) -> URL {
        FileManager.default.temporaryDirectory          // iOS system temp folder
            .appendingPathComponent("Music2", isDirectory: true)   // our app's subfolder
            .appendingPathComponent(songID, isDirectory: true)     // one folder per song
    }

    // Returns the folder path for a specific stem within a song
    // e.g. /tmp/Music2/mock_song_001/drums/
    // stem.rawValue converts the enum to its string name (.drums → "drums")
    // Does NOT create the folder - just builds the URL
    static func stemDir(songID: String, stem: StemType) -> URL {
        songDir(songID: songID)
            .appendingPathComponent(stem.rawValue, isDirectory: true)
    }

    // ── WRITE ─────────────────────────────────────────────────────────────────

    // Saves one audio chunk to disk and returns the URL where it was saved
    // This is the only function that actually touches the file system
    //
    // songID     - which song this chunk belongs to
    // stem       - which instrument track (.drums, .bass, .vocals, .other)
    // chunkIndex - position in the sequence (0 = first 5 sec, 1 = next 5 sec, etc.)
    // data       - the raw PCM bytes received from Lucas's server
    // ext        - file extension to use, either "pcm" or "wav"
    static func writeChunk(songID: String, stem: StemType, chunkIndex: Int, data: Data, ext: String) throws -> URL {

        // Get the folder path for this stem
        let dir = stemDir(songID: songID, stem: stem)

        // Create the folder if it doesn't exist yet
        // withIntermediateDirectories: true means it creates parent folders too
        // so /tmp/Music2/song123/drums/ all gets created in one call
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Build the filename with zero-padded chunk index
        // %04d pads the number to 4 digits so files sort correctly alphabetically
        // e.g. chunk_0000.pcm, chunk_0001.pcm ... chunk_0010.pcm (not chunk_10 jumping ahead)
        let filename = String(format: "chunk_%04d.%@", chunkIndex, ext)
        let fileURL = dir.appendingPathComponent(filename)

        // Write bytes to disk
        // .atomic means the file is written to a temp location first, then moved
        // this prevents a half-written file if the app crashes mid-write
        try data.write(to: fileURL, options: .atomic)

        // Return the final file path so the caller knows exactly where it landed
        // useful for debugging and for passing to the audio playback layer
        return fileURL
    }
}
