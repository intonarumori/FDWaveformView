//
//  FDAudioContextProtocol.swift
//  DMFSeq
//
//  Created by Daniel Langh on 2020. 03. 17..
//  Copyright © 2020. Daniel Langh. All rights reserved.
//

import UIKit

public protocol FDAudioContextReaderResultProtocol {
    var samplesToProcess: Int { get }
    var downSampledLength: Int { get }
    var filter: [Float] { get }
}

public protocol FDAudioContextReaderProtocol: class {
    var sampleMax: CGFloat { get }
    var samplesPerPixel: Int { get }
    var isCompleted: Bool { get }
    var error: Error? { get }
    
    func readNextBatch(sampleBuffer: inout Data) -> FDAudioContextReaderResultProtocol?
}

public protocol FDAudioContextProtocol: class {

    var totalSamples: Int { get }
    func getReader(slice: CountableRange<Int>,
                   targetSamples: Int,
                   format: FDWaveformRenderFormat) throws -> FDAudioContextReaderProtocol?
}
