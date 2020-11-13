//
// Copyright 2013 - 2017, William Entriken and the FDWaveformView contributors.
//
import UIKit
import AVFoundation

/// Holds audio information used for building waveforms
final class FDAudioContext: FDAudioContextProtocol {
    
    /// The audio asset URL used to load the context
    public let audioURL: URL
    
    /// Total number of samples in loaded asset
    public let totalSamples: Int
    
    /// Loaded asset
    public let asset: AVAsset
    
    // Loaded assetTrack
    public let assetTrack: AVAssetTrack
    
    // MARK: -
    
    private init(audioURL: URL, totalSamples: Int, asset: AVAsset, assetTrack: AVAssetTrack) {
        self.audioURL = audioURL
        self.totalSamples = totalSamples
        self.asset = asset
        self.assetTrack = assetTrack
        
        print("FDAudioContext created \(totalSamples)")
    }
    
    public static func load(fromAudioURL audioURL: URL,
                            completionHandler: @escaping (_ audioContext: FDAudioContext?) -> ()) {
        
        let asset = AVURLAsset(url: audioURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: NSNumber(value: true as Bool)])
        
        guard let assetTrack = asset.tracks(withMediaType: AVMediaType.audio).first else {
            NSLog("FDWaveformView failed to load AVAssetTrack")
            completionHandler(nil)
            return
        }
        
        asset.loadValuesAsynchronously(forKeys: ["duration"]) {
            var error: NSError?
            let status = asset.statusOfValue(forKey: "duration", error: &error)
            switch status {
            case .loaded:
                guard
                    let formatDescriptions = assetTrack.formatDescriptions as? [CMAudioFormatDescription],
                    let audioFormatDesc = formatDescriptions.first,
                    let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDesc)
                    else { break }
                
                let totalSamples = Int((asbd.pointee.mSampleRate) * Float64(asset.duration.value) / Float64(asset.duration.timescale))
                let audioContext = FDAudioContext(audioURL: audioURL, totalSamples: totalSamples, asset: asset, assetTrack: assetTrack)
                completionHandler(audioContext)
                return
                
            case .failed, .cancelled, .loading, .unknown:
                print("FDWaveformView could not load asset: \(error?.localizedDescription ?? "Unknown error")")
            @unknown default:
                print("FDWaveformView could not load asset: \(error?.localizedDescription ?? "Unknown error")")
            }
            
            completionHandler(nil)
        }
    }
    
    func getReader(slice: CountableRange<Int>, targetSamples: Int,
                   format: FDWaveformRenderFormat) throws -> FDAudioContextReaderProtocol {
        return try FDAudioContextReader(audioContext: self, slice: slice,
                                        targetSamples: targetSamples, type: format.type)
    }
}


// MARK: -

class FDAudioContextReader: FDAudioContextReaderProtocol {
    
    private let reader: AVAssetReader
    private let readerOutput: AVAssetReaderTrackOutput

    private(set) var sampleMax: CGFloat
    private(set) var samplesPerPixel: Int
    private var filter: [Float]
    
    // MARK: -
    
    deinit {
        reader.cancelReading()
    }
    
    init(audioContext: FDAudioContext,
         slice: CountableRange<Int>,
         targetSamples: Int,
         type: FDWaveformType) throws {
        
        self.reader = try AVAssetReader(asset: audioContext.asset)
        
        var channelCount = 1
        var sampleRate: CMTimeScale = 44100
        
        let formatDescriptions = audioContext.assetTrack.formatDescriptions as! [CMAudioFormatDescription]
        for item in formatDescriptions {
            guard let fmtDesc = CMAudioFormatDescriptionGetStreamBasicDescription(item) else {
                throw NSError(domain: "format description error", code: 1000, userInfo: nil)
            }
            channelCount = Int(fmtDesc.pointee.mChannelsPerFrame)
            sampleRate = Int32(fmtDesc.pointee.mSampleRate)
        }
        
        reader.timeRange = CMTimeRange(start: CMTime(value: Int64(slice.lowerBound), timescale: sampleRate),
                                       duration: CMTime(value: Int64(slice.count), timescale: sampleRate))
        
        let outputSettingsDict: [String : Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: audioContext.assetTrack,
                                                    outputSettings: outputSettingsDict)
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)
        self.readerOutput = readerOutput
        
        self.sampleMax = type.floorValue
        self.samplesPerPixel = max(1, channelCount * slice.count / targetSamples)
        self.filter = [Float](repeating: 1.0 / Float(samplesPerPixel), count: samplesPerPixel)
        
        // 16-bit samples
        reader.startReading()
    }

    
    func readNextBatch(sampleBuffer: inout [Float]) -> FDAudioContextReaderResultProtocol? {
        guard reader.status == .reading else {
            return nil
        }
        
        if let readSampleBuffer = readerOutput.copyNextSampleBuffer(),
            let readBuffer = CMSampleBufferGetDataBuffer(readSampleBuffer) {
            
            // Append audio sample buffer into our current sample buffer
            var readBufferLength = 0
            var readBufferPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(readBuffer,
                                        atOffset: 0,
                                        lengthAtOffsetOut: &readBufferLength,
                                        totalLengthOut: nil,
                                        dataPointerOut: &readBufferPointer)

            let data = Data(buffer: UnsafeBufferPointer(start: readBufferPointer, count: readBufferLength))
            let values: [Float] = FDAudioSampler.getValues(from: data)
            sampleBuffer.append(contentsOf: values)

            CMSampleBufferInvalidate(readSampleBuffer)
            
            let totalSamples = sampleBuffer.count / MemoryLayout<Float>.size
            let downSampledLength = totalSamples / samplesPerPixel
            let samplesToProcess = downSampledLength * samplesPerPixel
            
            if (samplesToProcess != totalSamples) {
                print("rounding")
            }

            return FDAudioContextReaderResult(samplesToProcess: samplesToProcess,
                                              downSampledLength: downSampledLength,
                                              filter: filter)
        } else {
            
            // Process the remaining samples that did not fit into samplesPerPixel at the end
            let samplesToProcess = sampleBuffer.count / MemoryLayout<Float>.size
            if samplesToProcess > 0 {
                
                let downSampledLength = 1
                let samplesPerPixel = samplesToProcess
                let filter = [Float](repeating: 1.0 / Float(samplesPerPixel), count: samplesPerPixel)

                return FDAudioContextReaderResult(samplesToProcess: samplesToProcess,
                                                  downSampledLength: downSampledLength,
                                                  filter: filter)
            } else {
                return nil
            }
        }
    }
    
    var isCompleted: Bool {
        // if (reader.status == AVAssetReaderStatusFailed || reader.status == AVAssetReaderStatusUnknown)
        // Something went wrong. Handle it or do not, depending on if you can get above to work
        return reader.status == .completed || true
    }
    
}

struct FDAudioContextReaderResult: FDAudioContextReaderResultProtocol {
    var samplesToProcess: Int
    var downSampledLength: Int
    var filter: [Float]
}

//extension AVAssetReader.Status : CustomStringConvertible {
//    public var description: String {
//        switch self{
//        case .reading: return "reading"
//        case .unknown: return "unknown"
//        case .completed: return "completed"
//        case .failed: return "failed"
//        case .cancelled: return "cancelled"
//        @unknown default:
//            fatalError()
//        }
//    }
//}
