//
//  File.swift
//  
//
//  Created by Daniel Langh on 2020. 11. 12..
//

import UIKit

public protocol FDWaveformPlotter: class {
    func plotWaveformGraph(_ values: [CGFloat],
                           maximumValue: CGFloat,
                           minimumValue: CGFloat,
                           scale: CGFloat,
                           imageSize: CGSize,
                           plotColor: UIColor) throws -> UIImage
}

// MARK: -

public class FDWaveformFillPlotter: FDWaveformPlotter {
    
    struct PlotError: Error {
        let message: String
    }
    
    /**
     Processes the given sample buffer data, downsamples it to a CGFloat array.
     
     - parameter values: values to plot
     - parameter maximumValue: maximum value for scaling
     - parameter minimumValue: minimum value for scaling
     - parameter scale: scale
     - parameter imageSize: image size
     - parameter plotColor: color of the plot
     */
    public func plotWaveformGraph(_ values: [CGFloat],
                                  maximumValue: CGFloat,
                                  minimumValue: CGFloat,
                                  scale: CGFloat,
                                  imageSize: CGSize,
                                  plotColor: UIColor) throws -> UIImage {
        
        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)
        
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            throw PlotError(message: "FDWaveformPlotter failed to get graphics context")
        }
        // Scale context to account for scaling applied to image
        context.scaleBy(x: 1 / scale, y: 1 / scale)
        context.setShouldAntialias(false)
        context.setAlpha(1.0)
        context.setLineWidth(1.0 / scale)
        context.setStrokeColor(plotColor.cgColor)
        
        let verticalRange = maximumValue - minimumValue

        let sampleDrawingScale: CGFloat
        if verticalRange == 0 {
            sampleDrawingScale = 0
        } else {
            sampleDrawingScale = (imageSize.height * scale) / 2 / verticalRange
        }
        
        let verticalMiddle = (imageSize.height * scale) / 2
        
        for (index, sample) in values.enumerated() {
            let x = CGFloat(index)
            let height = (sample - minimumValue) * sampleDrawingScale
            context.move(to: CGPoint(x: x, y: verticalMiddle - height))
            context.addLine(to: CGPoint(x: CGFloat(x), y: verticalMiddle + height))
            context.strokePath()
        }
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            throw PlotError(message: "FDWaveformPlotter failed to get waveform image from context")
        }
        
        return image
    }
}

// MARK: -

public class FDWaveformLinePlotter: FDWaveformPlotter {
    
    struct PlotError: Error {
        let message: String
    }
    
    /**
     Processes the given sample buffer data, downsamples it to a CGFloat array.
     
     - parameter values: values to plot
     - parameter maximumValue: maximum value for scaling
     - parameter minimumValue: minimum value for scaling
     - parameter scale: scale
     - parameter imageSize: image size
     - parameter plotColor: color of the plot
     */
    public func plotWaveformGraph(_ values: [CGFloat],
                                  maximumValue: CGFloat,
                                  minimumValue: CGFloat,
                                  scale: CGFloat,
                                  imageSize: CGSize,
                                  plotColor: UIColor) throws -> UIImage {
        
        print("IMAGESIZE: \(imageSize)")
        
        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)
        
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            throw PlotError(message: "FDWaveformPlotter failed to get graphics context")
        }
        // Scale context to account for scaling applied to image
        context.scaleBy(x: 1 / scale, y: 1 / scale)
        context.setShouldAntialias(false)
        context.setAlpha(1.0)
        context.setLineWidth(1.0 / scale)
        context.setStrokeColor(plotColor.cgColor)
        context.setFillColor(plotColor.cgColor)
        
        let verticalRange = maximumValue - minimumValue

        let sampleDrawingScale: CGFloat
        if verticalRange == 0 {
            sampleDrawingScale = 0
        } else {
            sampleDrawingScale = (imageSize.height * scale) / 2 / verticalRange
        }
        
        let verticalMiddle = (imageSize.height * scale) / 2

  //      context.move(to: CGPoint(x: 0, y: verticalMiddle))

        for (index, sample) in values.enumerated() {
            let height = -(sample - minimumValue) * sampleDrawingScale
            let x = CGFloat(index)
            let y = verticalMiddle + height
            //context.fillEllipse(in: CGRect(x: x, y: y, width: 4, height: 4))
            context.fill(CGRect(x: x, y: y, width: 4, height: 4))
//            context.addLine(to: CGPoint(x: x, y: verticalMiddle + height))
        }
    //    context.strokePath()

        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            throw PlotError(message: "FDWaveformPlotter failed to get waveform image from context")
        }
        
        return image
    }
}

