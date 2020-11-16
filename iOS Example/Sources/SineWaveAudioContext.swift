//
//  File.swift
//  
//
//  Created by Daniel Langh on 2020. 03. 17..
//

import UIKit
import Foundation
import FDWaveformView

class SineWaveAudioContext: FDAudioContextProtocol {
    var totalSamples: Int
    var samples: [Float]
    
    init() {
        // generate sine
        totalSamples = 44100
        
        samples = Array(repeating: 0, count: totalSamples)
        
        for (index, _) in samples.enumerated() {
            samples[index] = Float(index) / Float(totalSamples)
        }
        
//        var phase: Float = 0
//        for (index, _) in samples.enumerated() {
//            samples[index] = Float(sin(phase) * 0.5)
//            phase += 0.001
//        }
    }
    
    func getReader(slice: CountableRange<Int>, targetSamples: Int,
                   format: FDWaveformRenderFormat) throws -> FDAudioContextReaderProtocol {
        return SineWaveAudioContextReader(context: self, slice: slice, targetSamples: targetSamples)
    }
}

class SineWaveAudioContextReader: FDAudioContextReaderProtocol {
    var sampleMax: CGFloat = 0
    var samplesPerPixel: Int = 0
    var filter: [Float]
    
    var slice: CountableRange<Int>

    var isCompleted: Bool = false
    
    private let batchSize = 4000
    private var currentIndex = 0
    
    var error: Error?
    
    let context: SineWaveAudioContext
    
    init(context: SineWaveAudioContext, slice: CountableRange<Int>, targetSamples: Int) {
        self.context = context
        self.slice = slice
        
        let channelCount = 1
        self.sampleMax = 0
        self.samplesPerPixel = max(1, channelCount * slice.count / targetSamples)
        self.filter = [Float](repeating: 1.0 / Float(samplesPerPixel), count: samplesPerPixel)
        
        currentIndex = slice.startIndex
    }
    
    func readNextBatch(sampleBuffer: inout [Float]) -> FDAudioContextReaderResultProtocol? {
        
        guard currentIndex < slice.endIndex else {
            isCompleted = true
            return nil
        }

        let startIndex = currentIndex
        let endIndex = min(slice.endIndex, min(context.samples.count, startIndex + batchSize))
        
        let sampleBatch = context.samples[currentIndex..<endIndex]
        
        isCompleted = (endIndex == slice.endIndex)
        
        currentIndex = endIndex
        sampleBuffer += sampleBatch
        
        let totalSamples = sampleBuffer.count
        let downSampledLength = totalSamples / samplesPerPixel
        let samplesToProcess = downSampledLength * samplesPerPixel
        
        //print("BATCH: \(currentIndex) downSampledLength:\(downSampledLength) samplesToProcess: \(samplesToProcess)")
        
        return FDSineWaveAudioContextReaderResult(
            samplesToProcess: samplesToProcess,
            downSampledLength: downSampledLength,
            filter: filter)
    }
}

struct FDSineWaveAudioContextReaderResult: FDAudioContextReaderResultProtocol {
    var samplesToProcess: Int
    var downSampledLength: Int
    var filter: [Float]
}
