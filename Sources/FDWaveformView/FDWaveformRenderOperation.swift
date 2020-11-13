//
// Copyright 2013 - 2017, William Entriken and the FDWaveformView contributors.
//
import UIKit
import Accelerate

public struct FDWaveformRenderFormat {
    
    /// The type of waveform to render
    let type: FDWaveformType
    
    /// The color of the waveform
    let wavesColor: UIColor
    
    /// The scale factor to apply to the rendered image (usually the current screen's scale)
    let scale: CGFloat
    
    /// Whether the resulting image size should be as close as possible to imageSize (approximate)
    /// or whether it should match it exactly. Right now there is no support for matching exactly.
    // TODO: Support rendering operations that always match the desired imageSize passed in.
    //       Right now the imageSize passed in to the render operation might not match the
    //       resulting image's size. This flag is hard coded here to convey that.
    let constrainImageSizeToExactlyMatch = false
}

// MARK: -

/// Operation used for rendering waveform images
final public class FDWaveformRenderOperation: Operation {
    
    /// The audio context used to build the waveform
    public let audioContext: FDAudioContextProtocol
    
    /// Size of waveform image to render
    public let imageSize: CGSize
    
    /// Range of samples within audio asset to build waveform for
    public let sampleRange: CountableRange<Int>
    
    /// Format of waveform image
    public let format: FDWaveformRenderFormat
    
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
    
    // MARK: -
    
    init(audioContext: FDAudioContextProtocol, imageSize: CGSize,
         sampleRange: CountableRange<Int>? = nil,
         format: FDWaveformRenderFormat? = nil,
         completionHandler: @escaping (_ image: UIImage?) -> ()) {
        
        self.audioContext = audioContext
        self.imageSize = imageSize
        self.sampleRange = sampleRange ?? 0..<audioContext.totalSamples
        self.format = format ?? FDWaveformRenderFormat(type: .linear, wavesColor: .blue, scale: 1)
        self.completionHandler = completionHandler
        
        super.init()
        
        self.completionBlock = { [weak self] in
            guard let `self` = self else { return }
            self.completionHandler(self.renderedImage)
            self.renderedImage = nil
        }
    }
    
    // MARK: - Lifecycle
    
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
    
    // MARK: -
    
    private func render() {
        
        var image: UIImage?
        
        defer {
            finish(with: image)
        }
        
        guard
            sampleRange.isEmpty == false,
            imageSize.width > 0,
            imageSize.height > 0
        else {
            finish(with: nil)
            return
        }
        
        let targetSamples = Int(imageSize.width * format.scale)

        guard let (samples, sampleMax) = sliceAsset(withRange: sampleRange, andDownsampleTo: targetSamples) else {
            return
        }

        do {
            guard !isCancelled else {
                return
            }
            
            let imageSize = CGSize(width: CGFloat(samples.count) / format.scale,
                                   height: self.imageSize.height)

            image = try FDWaveformPlotter.plotWaveformGraph(
                samples,
                maximumValue: sampleMax,
                minimumValue: format.type.floorValue,
                scale: format.scale,
                imageSize: imageSize,
                plotColor: format.wavesColor)
            
        } catch let error {
            print("Plotter error \(error)")
            return
        }
    }
    
    /**
     Read the asset and create a lower resolution set of samples.
     - parameter slice:
     */
    func sliceAsset(withRange slice: CountableRange<Int>,
                    andDownsampleTo targetSamples: Int) -> (values: [CGFloat], maximumValue: CGFloat)? {
        
        guard !isCancelled else { return nil }
        
        guard
            slice.isEmpty == false,
            targetSamples > 0
        else {
            return nil
        }
        
        do {
            let reader = try audioContext.getReader(slice: slice, targetSamples: targetSamples, format: format)
            
            var outputSamples: [CGFloat] = []
            var sampleBuffer = [Float]()
            var maximumValue: CGFloat = reader.sampleMax
            let samplesPerPixel = reader.samplesPerPixel

            let noiseFloor: Float
            let normalize: Bool
            switch format.type {
            case .linear:
                noiseFloor = 0
                normalize = false
            case .logarithmic(let floor):
                noiseFloor = Float(floor)
                normalize = true
            }

            while let result = reader.readNextBatch(sampleBuffer: &sampleBuffer) {
                
                guard !isCancelled else { return nil }
                
                if result.samplesToProcess > 0 {
                    outputSamples += FDAudioSampler.processSamples(
                        inputData: &sampleBuffer,
                       // inputLength: result.samplesToProcess,
                        maximumValue: &maximumValue,
                        formatType: format.type,
                        outputLength: result.downSampledLength,
                        stride: samplesPerPixel,
                        filter: result.filter,
                        normalize: normalize,
                        noiseFloor: noiseFloor)
                }
            }

            if reader.isCompleted {
                return (outputSamples, maximumValue)
            } else {
                return nil
            }

        } catch {
            print("FDWaveformRenderOperation failed to read audio: \(error)")
            return nil
        }
    }
}
