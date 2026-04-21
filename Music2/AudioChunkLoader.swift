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
    
    /// Loads an audio file and converts it to mono Int16 PCM samples at the target sample rate.
    /// - Parameters:
    ///   - fileURL: URL of the stem file
    ///   - targetSampleRate: desired sample rate for BLE streaming
    /// - Returns: mono Int16 samples
    static func loadPCM16MonoSamples(
        from fileURL: URL,
        targetSampleRate: Double = 8_000
    ) throws -> [Int16] {
        
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
        
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioChunkLoaderError.conversionFailed
        }
        
        let ratio = targetSampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 1024
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else {
            throw AudioChunkLoaderError.couldNotCreatePCMBuffer
        }
        
        var conversionError: NSError?
        var hasProvidedInput = false
        
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if hasProvidedInput {
                outStatus.pointee = .noDataNow
                return nil
            } else {
                hasProvidedInput = true
                outStatus.pointee = .haveData
                return inputBuffer
            }
        }
        
        let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
        
        if status == .error || conversionError != nil {
            throw conversionError ?? AudioChunkLoaderError.conversionFailed
        }
        
        guard let int16ChannelData = outputBuffer.int16ChannelData else {
            throw AudioChunkLoaderError.unsupportedChannelData
        }
        
        let frameCount = Int(outputBuffer.frameLength)
        let samplesPointer = int16ChannelData[0]
        
        var samples: [Int16] = []
        samples.reserveCapacity(frameCount)
        
        for i in 0..<frameCount {
            samples.append(samplesPointer[i])
        }
        
        return samples
    }
    
    /// Convenience wrapper if you still want mono PCM bytes.
    static func loadPCM16MonoData(
        from fileURL: URL,
        targetSampleRate: Double = 8_000
    ) throws -> Data {
        let samples = try loadPCM16MonoSamples(from: fileURL, targetSampleRate: targetSampleRate)
        return pcmData(from: samples)
    }
    
    /// Converts Int16 samples to little-endian PCM bytes.
    static func pcmData(from samples: [Int16]) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        
        for sample in samples {
            var sampleLE = sample.littleEndian
            withUnsafeBytes(of: &sampleLE) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        
        return data
    }
    
    /// Builds stereo interleaved PCM from one mono stem.
    /// Left = mono sample, Right = same mono sample
    static func makeStereoPCMDataDuplicatingMono(_ monoSamples: [Int16]) -> Data {
        var stereoData = Data(capacity: monoSamples.count * 2 * MemoryLayout<Int16>.size)
        
        for sample in monoSamples {
            var left = sample.littleEndian
            var right = sample.littleEndian
            
            withUnsafeBytes(of: &left) { stereoData.append(contentsOf: $0) }
            withUnsafeBytes(of: &right) { stereoData.append(contentsOf: $0) }
        }
        
        return stereoData
    }
    
    /// Builds stereo interleaved PCM from two mono stems.
    /// Left = leftSamples[i], Right = rightSamples[i]
    /// If lengths differ, pads the shorter side with zeros.
    static func makeStereoPCMData(
        left leftSamples: [Int16],
        right rightSamples: [Int16]
    ) -> Data {
        let frameCount = min(leftSamples.count, rightSamples.count)
        var stereoData = Data(capacity: frameCount * 2 * MemoryLayout<Int16>.size)
        
        for i in 0..<frameCount {
            let leftSample = i < leftSamples.count ? leftSamples[i] : 0
            let rightSample = i < rightSamples.count ? rightSamples[i] : 0
            
            var leftLE = leftSample.littleEndian
            var rightLE = rightSample.littleEndian
            
            withUnsafeBytes(of: &leftLE) { stereoData.append(contentsOf: $0) }
            withUnsafeBytes(of: &rightLE) { stereoData.append(contentsOf: $0) }
        }
        
        return stereoData
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
