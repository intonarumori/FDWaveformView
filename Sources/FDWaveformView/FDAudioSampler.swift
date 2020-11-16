//
//  File.swift
//  
//
//  Created by Daniel Langh on 2020. 11. 12..
//

import UIKit
import Accelerate

class FDAudioSampler {
    
    /**
     Processes the given sample buffer data, downsamples it to a CGFloat array.
     
     - parameter sampleBuffer: incoming sample data expected as a `Float`
     - parameter sampleMax: maximum value for samples
     - parameter outputSamples: generated downsampled data
     - parameter samplesToProcess: number of samples to use for downsampling
     - parameter downSampledLength: length of generated downsampled data
     - parameter samplesPerPixel: number of samples per pixel
     - parameter filter
     */
    static func processSamples(inputData: inout [Float],
                               maximumValue: inout CGFloat,
                               formatType: FDWaveformType,
                               outputLength: Int,
                               stride: Int,
                               filter: [Float],
                               normalize: Bool = false,
                               noiseFloor: Float = 0) -> [CGFloat] {
        
        var processingBuffer: [Float] = inputData // getValues(from: inputData)
        inputData.removeFirst(processingBuffer.count)

        convertToAbsoluteValues(&processingBuffer)
        
        if normalize {
            normalizeValues(&processingBuffer)
            clampValues(&processingBuffer, minimum: noiseFloor, maximum: 0)
        }
        
        //Downsample and average
        var downSampledData = Array<Float>(repeating: 0.0, count: outputLength)
        downSampleValues(processingBuffer, stride: stride, filter: filter, output: &downSampledData)

        let cgSampledData = downSampledData.map { CGFloat($0) }
        maximumValue = cgSampledData.reduce(maximumValue, { max($0, $1) })
        
        return cgSampledData
    }
    
    static func normalizeValues(_ data: inout [Float]) {
        let count = vDSP_Length(data.count)
        // Convert samples to a log scale
        //var zero: Float = 32768.0 // for Int16 integers
        var zero: Float = 1.0       // the input number representing 0dB on the output
        vDSP_vdbcon(data, 1,        // input vector + stride
                    &zero,          // zero reference
                    &data, 1,       // output vector + stride
                    count,          // number of elements
                    1)              // power = 0, amplitude = 1
    }
    
    static func clampValues(_ data: inout [Float], minimum: Float, maximum: Float) {
        let count = vDSP_Length(data.count)
        var floor = minimum
        var ceil = maximum
        vDSP_vclip(data, 1,         // input vector + stride
                   &floor,          // low clipping threshold
                   &ceil,           // high clipping threshold
                   &data, 1,        // output vector + stride
                   count)           // number of elements
    }
    
    static func convertToAbsoluteValues(_ data: inout [Float]) {
        //Take the absolute values to get amplitude
        let sampleCount = vDSP_Length(data.count)
        vDSP_vabs(data, 1, &data, 1, sampleCount)
    }
    
    static func downSampleValues(_ input: [Float], stride: Int, filter: [Float], output: inout [Float]) {
        vDSP_desamp(input,
                    vDSP_Stride(stride),
                    filter, &output,
                    vDSP_Length(output.count),
                    vDSP_Length(filter.count)
        )
    }
    
    static func getValues<T: Numeric>(from data: Data) -> [T] {
        
        let length = data.count / MemoryLayout<T>.size

        let result = data.withUnsafeBytes { bytes -> [T] in
            var processingBuffer = Array<T>(repeating: 0, count: length)
            _ = processingBuffer.withUnsafeMutableBytes { bytes.copyBytes(to: $0, count: data.count) }
            return processingBuffer
        }
        return result
    }
}
