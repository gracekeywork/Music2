//
//  AudioChunkLoader.swift
//  Music2
//
//  Created by grace keywork on 4/13/26.
//

import Foundation
import AVFoundation

enum AudioChunkLoaderError: Error {
    case couldNotCreatePCMBuffer
    case unsupportedChannelData
    case conversionFailed
}

final class AudioChunkLoader {
    
    /// Loads an audio file and converts it to mono Int16 PCM data.
    /// - Parameters:
    ///   - fileURL: URL of the stem file
    ///   - targetSampleRate: desired sample rate for BLE streaming
    /// - Returns: raw PCM Int16 bytes in little-endian order
    static func loadPCM16MonoData(
        from fileURL: URL,
        targetSampleRate: Double = 8_000
    ) throws -> Data {
        
        let inputFile = try AVAudioFile(forReading: fileURL)
        let inputFormat = inputFile.processingFormat
        
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioChunkLoaderError.conversionFailed
        }
        
        let inputFrameCount = AVAudioFrameCount(inputFile.length)
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: inputFrameCount
        ) else {
            throw AudioChunkLoaderError.couldNotCreatePCMBuffer
        }
        
        try inputFile.read(into: inputBuffer)
        
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        guard let converter else {
            throw AudioChunkLoaderError.conversionFailed
        }
        
        // Rough capacity scaled to output sample rate
        let ratio = targetSampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 1024
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else {
            throw AudioChunkLoaderError.couldNotCreatePCMBuffer
        }
        
        var conversionError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
        
        if status == .error || conversionError != nil {
            throw conversionError ?? AudioChunkLoaderError.conversionFailed
        }
        
        guard let int16ChannelData = outputBuffer.int16ChannelData else {
            throw AudioChunkLoaderError.unsupportedChannelData
        }
        
        let frameCount = Int(outputBuffer.frameLength)
        let samples = int16ChannelData[0]
        
        var pcmData = Data(capacity: frameCount * MemoryLayout<Int16>.size)
        
        for i in 0..<frameCount {
            var sampleLE = Int16(samples[i]).littleEndian
            withUnsafeBytes(of: &sampleLE) { bytes in
                pcmData.append(contentsOf: bytes)
            }
        }
        
        return pcmData
    }
    
    /// Splits raw PCM data into fixed-size chunks.
    static func splitIntoChunks(_ data: Data, chunkSize: Int) -> [Data] {
        guard chunkSize > 0 else { return [] }
        
        var chunks: [Data] = []
        var start = 0
        
        while start < data.count {
            let end = min(start + chunkSize, data.count)
            chunks.append(data.subdata(in: start..<end))
            start = end
        }
        
        return chunks
    }
}
