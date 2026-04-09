//
//  EQManager.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import AVFoundation
import Observation

enum EQPreset: String, CaseIterable, Identifiable {
    case flat       = "Flat"
    case acoustic   = "Acoustic"
    case bassBoost  = "Bass Boost"
    case classical  = "Classical"
    case electronic = "Electronic"
    case rock       = "Rock"
    case vocal      = "Vocal"
    case custom     = "Custom"

    var id: String { rawValue }

    // gains in dB for 10 bands: 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k
    var gains: [Float] {
        switch self {
        case .flat:       return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .acoustic:   return [5, 4.5, 4, 3.5, 2.5, 1.5, 0, -1, -1, -1]
        case .bassBoost:  return [6, 5.5, 5, 3, 0, 0, 0, 0, 0, 0]
        case .classical:  return [3.5, 3, 2.5, 0, 0, 0, -2, -3, -3.5, -4]
        case .electronic: return [4, 3.5, 1, -1.5, -2, 1.5, 2, 3.5, 3.5, 4]
        case .rock:       return [4.5, 3, -1.5, -2.5, -1, 2, 3.5, 4.5, 4.5, 5]
        case .vocal:      return [-2, -3, -2, 1, 3.5, 4, 3, 2, 1, -1]
        case .custom:     return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        }
    }
}

let eqBandFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
let eqBandLabels = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]

/// manages the 10-band parametric EQ node
@Observable
final class EQManager {

    static let shared = EQManager()

    let eqNode = AVAudioUnitEQ(numberOfBands: 10)

    var isEnabled: Bool = true {
        didSet { eqNode.bypass = !isEnabled }
    }

    var gains: [Float] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] {
        didSet { applyGains() }
    }

    var preamplifierGain: Float = 0 {
        didSet { eqNode.globalGain = preamplifierGain }
    }

    var selectedPreset: EQPreset = .flat {
        didSet {
            if selectedPreset != .custom {
                gains = selectedPreset.gains
            }
        }
    }

    private init() {
        setupBands()
    }

    private func setupBands() {
        for (i, freq) in eqBandFrequencies.enumerated() {
            let band = eqNode.bands[i]
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
    }

    private func applyGains() {
        for (i, gain) in gains.enumerated() {
            eqNode.bands[i].gain = gain
        }
        // mark as custom if the gains no longer match the selected preset
        if selectedPreset != .custom && gains != selectedPreset.gains {
            selectedPreset = .custom
        }
    }

    func applyPreset(_ preset: EQPreset) {
        selectedPreset = preset
        gains = preset.gains
    }

    func nudgePreamplifier(by delta: Float) {
        preamplifierGain = max(-12, min(12, preamplifierGain + delta))
    }
}
