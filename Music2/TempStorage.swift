import Foundation

enum TempStorage {
    static func songDir(songID: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Music2", isDirectory: true)
            .appendingPathComponent(songID, isDirectory: true)
    }

    static func stemDir(songID: String, stem: StemType) -> URL {
        songDir(songID: songID).appendingPathComponent(stem.rawValue, isDirectory: true)
    }

    static func writeChunk(songID: String, stem: StemType, chunkIndex: Int, data: Data, ext: String) throws -> URL {
        let dir = stemDir(songID: songID, stem: stem)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = String(format: "chunk_%04d.%@", chunkIndex, ext)
        let fileURL = dir.appendingPathComponent(filename)

        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}