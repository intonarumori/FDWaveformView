//
// Copyright 2013 - 2017, William Entriken and the FDWaveformView contributors.
//
import UIKit
import Accelerate

/// Format options for FDWaveformRenderOperation
//MAYBE: Make this public
public struct FDWaveformRenderFormat {
    
    /// The type of waveform to render
    //TODO: make this public after reconciling FDWaveformView.WaveformType and FDWaveformType
    var type: FDWaveformType
    
    /// The color of the waveform
    internal var wavesColor: UIColor
    
    /// The scale factor to apply to the rendered image (usually the current screen's scale)
    public var scale: CGFloat
    
    /// Whether the resulting image size should be as close as possible to imageSize (approximate)
    /// or whether it should match it exactly. Right now there is no support for matching exactly.
    // TODO: Support rendering operations that always match the desired imageSize passed in.
    //       Right now the imageSize passed in to the render operation might not match the
    //       resulting image's size. This flag is hard coded here to convey that.
    public let constrainImageSizeToExactlyMatch = false
    
    // To make these public, you must implement them
    // See http://stackoverflow.com/questions/26224693/how-can-i-make-public-by-default-the-member-wise-initialiser-for-structs-in-swif
    public init() {
        self.init(type: .linear,
                  wavesColor: .black,
                  scale: UIScreen.main.scale)
    }
    
    init(type: FDWaveformType, wavesColor: UIColor, scale: CGFloat) {
        self.type = type
        self.wavesColor = wavesColor
        self.scale = scale
    }
}

/// Operation used for rendering waveform images
final public class FDWaveformRenderOperation: Operation {
    
    /// The audio context used to build the waveform
    let audioContext: FDAudioContextProtocol
    
    /// Size of waveform image to render
    public let imageSize: CGSize
    
    /// Range of samples within audio asset to build waveform for
    public let sampleRange: CountableRange<Int>
    
    /// Format of waveform image
    let format: FDWaveformRenderFormat
    
    // MARK: - NSOperation Overrides
    
    public override var isAsynchronous: Bool { return true }
    
    private var _isExecuting = false
    public override var isExecuting: Bool { return _isExecuting }
    
    private var _isFinished = false
    public override var isFinished: Bool { return _isFinished }
    
    // MARK: - Private
    
    ///  Handler called when the rendering has completed. nil UIImage indicates that there was an error during processing.
    private let completionHandler: (UIImage?) -> ()
    
    /// Final rendered image. Used to hold image for completionHandler.
    private var renderedImage: UIImage?
    
    init(audioContext: FDAudioContextProtocol, imageSize: CGSize, sampleRange: CountableRange<Int>? = nil, format: FDWaveformRenderFormat = FDWaveformRenderFormat(), completionHandler: @escaping (_ image: UIImage?) -> ()) {
        self.audioContext = audioContext
        self.imageSize = imageSize
        self.sampleRange = sampleRange ?? 0..<audioContext.totalSamples
        self.format = format
        self.completionHandler = completionHandler
        
        super.init()
        
        self.completionBlock = { [weak self] in
            guard let `self` = self else { return }
            self.completionHandler(self.renderedImage)
            self.renderedImage = nil
        }
    }
    
    public override func start() {
        guard !isExecuting && !isFinished && !isCancelled else { return }
        
        willChangeValue(forKey: "isExecuting")
        _isExecuting = true
        didChangeValue(forKey: "isExecuting")
        
        if #available(iOS 8.0, *) {
            DispatchQueue.global(qos: .background).async { self.render() }
        } else {
            DispatchQueue.global(priority: .background).async { self.render() }
        }
    }
    
    private func finish(with image: UIImage?) {
        guard !isFinished && !isCancelled else { return }
        
        renderedImage = image
        
        // completionBlock called automatically by NSOperation after these values change
        willChangeValue(forKey: "isExecuting")
        willChangeValue(forKey: "isFinished")
        _isExecuting = false
        _isFinished = true
        didChangeValue(forKey: "isExecuting")
        didChangeValue(forKey: "isFinished")
    }
    
    private func render() {
        guard
            !sampleRange.isEmpty,
            imageSize.width > 0, imageSize.height > 0
            else {
                finish(with: nil)
                return
        }
        
        let targetSamples = Int(imageSize.width * format.scale)
        
        let image: UIImage? = {
            guard
                let (samples, sampleMax) = sliceAsset(withRange: sampleRange, andDownsampleTo: targetSamples),
                let image = plotWaveformGraph(samples, maximumValue: sampleMax, zeroValue: format.type.floorValue)
                else { return nil }
            
            return image
        }()
        
        finish(with: image)
    }
    
    /// Read the asset and create a lower resolution set of samples
    func sliceAsset(withRange slice: CountableRange<Int>, andDownsampleTo targetSamples: Int) -> (samples: [CGFloat], sampleMax: CGFloat)? {
        guard !isCancelled else { return nil }
        
        guard
            !slice.isEmpty,
            targetSamples > 0,
            let reader = try? audioContext.getReader(slice: slice, targetSamples: targetSamples, format: format)
        else {
            return nil
        }
        
        var outputSamples = [CGFloat]()
        var sampleBuffer = Data()
        var sampleMax: CGFloat = reader.sampleMax
        let samplesPerPixel = reader.samplesPerPixel

        while let result = reader.readNextBatch(sampleBuffer: &sampleBuffer) {
            guard !isCancelled else { return nil }

            if result.samplesToProcess > 0 {
                processSamples(fromData: &sampleBuffer,
                               sampleMax: &sampleMax,
                               outputSamples: &outputSamples,
                               samplesToProcess: result.samplesToProcess,
                               downSampledLength: result.downSampledLength,
                               samplesPerPixel: samplesPerPixel,
                               filter: result.filter)
            }
        }
        
        if reader.isCompleted {
            return (outputSamples, sampleMax)
        } else {
            print("FDWaveformRenderOperation failed to read audio: \(String(describing: reader.error))")
            return nil
        }
    }
    
    // TODO: report progress? (for issue #2)
    func processSamples(fromData sampleBuffer: inout Data, sampleMax: inout CGFloat,
                        outputSamples: inout [CGFloat], samplesToProcess: Int,
                        downSampledLength: Int, samplesPerPixel: Int, filter: [Float]) {
        
        sampleBuffer.withUnsafeBytes { bytes in
            guard let samples = bytes.bindMemory(to: Int16.self).baseAddress else {
                return
            }
            
            var processingBuffer = [Float](repeating: 0.0, count: samplesToProcess)
            
            let sampleCount = vDSP_Length(samplesToProcess)
            
            //Convert 16bit int samples to floats
            vDSP_vflt16(samples, 1, &processingBuffer, 1, sampleCount)
            
            //Take the absolute values to get amplitude
            vDSP_vabs(processingBuffer, 1, &processingBuffer, 1, sampleCount)
            
            //Let current type further process the samples
            format.type.process(normalizedSamples: &processingBuffer)
            
            //Downsample and average
            var downSampledData = [Float](repeating: 0.0, count: downSampledLength)
            vDSP_desamp(processingBuffer,
                        vDSP_Stride(samplesPerPixel),
                        filter, &downSampledData,
                        vDSP_Length(downSampledLength),
                        vDSP_Length(samplesPerPixel))
            
            let downSampledDataCG = downSampledData.map { (value: Float) -> CGFloat in
                let element = CGFloat(value)
                if element > sampleMax { sampleMax = element }
                return element
            }
            
            // Remove processed samples
            sampleBuffer.removeFirst(samplesToProcess * MemoryLayout<Int16>.size)
            
            outputSamples += downSampledDataCG
        }
    }
    
    // TODO: report progress? (for issue #2)
    func plotWaveformGraph(_ samples: [CGFloat], maximumValue max: CGFloat, zeroValue min: CGFloat) -> UIImage? {
        guard !isCancelled else { return nil }
        
        let imageSize = CGSize(width: CGFloat(samples.count) / format.scale,
                               height: self.imageSize.height)
        
        UIGraphicsBeginImageContextWithOptions(imageSize, false, format.scale)
        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else {
            NSLog("FDWaveformView failed to get graphics context")
            return nil
        }
        context.scaleBy(x: 1 / format.scale, y: 1 / format.scale) // Scale context to account for scaling applied to image
        context.setShouldAntialias(false)
        context.setAlpha(1.0)
        context.setLineWidth(1.0 / format.scale)
        context.setStrokeColor(format.wavesColor.cgColor)
        
        let sampleDrawingScale: CGFloat
        if max == min {
            sampleDrawingScale = 0
        } else {
            sampleDrawingScale = (imageSize.height * format.scale) / 2 / (max - min)
        }
        let verticalMiddle = (imageSize.height * format.scale) / 2
        for (x, sample) in samples.enumerated() {
            let height = (sample - min) * sampleDrawingScale
            context.move(to: CGPoint(x: CGFloat(x), y: verticalMiddle - height))
            context.addLine(to: CGPoint(x: CGFloat(x), y: verticalMiddle + height))
            context.strokePath();
        }
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            NSLog("FDWaveformView failed to get waveform image from context")
            return nil
        }
        
        return image
    }
}
