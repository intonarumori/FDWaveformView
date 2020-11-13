//
//  FDWaveformType.swift
//  DMFSeq
//
//  Created by Daniel Langh on 2020. 11. 11..
//  Copyright © 2020. Daniel Langh. All rights reserved.
//

import Foundation
import Accelerate


/**
 Waveform type.
 - `linear`
 - `logarithmic`
*/
public enum FDWaveformType {

    /// Waveform is rendered using a linear scale
    case linear

    /// Waveform is rendered using a logarithmic scale
    ///   noiseFloor: The "zero" level (in dB)
    case logarithmic(noiseFloor: CGFloat)
}

extension FDWaveformType {
    public var floorValue: CGFloat {
        switch self {
        case .linear: return 0
        case .logarithmic(let noiseFloor): return noiseFloor
        }
    }
}

extension FDWaveformType: Equatable {
    public static func ==(lhs: FDWaveformType, rhs: FDWaveformType) -> Bool {
        switch (lhs, rhs) {
        case (.linear, linear):
            return true
        case (.logarithmic(let lhsNoiseFloor), .logarithmic(let rhsNoiseFloor)):
            return lhsNoiseFloor == rhsNoiseFloor
        default:
            return false
        }
    }
}
