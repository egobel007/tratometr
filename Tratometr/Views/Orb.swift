import SwiftUI

enum OrbMood: Equatable {
    case idle, listen, think
}

/// Smoothly animated parameters for the orb shader. Not observed by SwiftUI:
/// the TimelineView asks for a fresh frame every display refresh.
final class OrbEngine {
    private(set) var phase: Double = 0
    private(set) var energy: Double = 0
    private(set) var tintAmount: Double = 0
    private(set) var scale: Double = 1
    var tint = SIMD3<Float>(1, 1, 1)
    var tilt = SIMD2<Float>(0, 0)

    private var energyTarget: Double = 0
    private var speed: Double = 1
    private var speedTarget: Double = 1
    private var tintTarget: Double = 0
    private var scaleTarget: Double = 1
    private var voiceBoost: Double = 0
    private var last: Double?

    func apply(_ mood: OrbMood) {
        switch mood {
        case .idle: energyTarget = 0; speedTarget = 1
        case .listen: energyTarget = 0.3; speedTarget = 1.7
        case .think: energyTarget = 0.55; speedTarget = 3.2
        }
    }

    func voice(_ level: Double) { voiceBoost = max(voiceBoost, level) }

    func burst(_ rgb: SIMD3<Float>) {
        tint = rgb
        tintTarget = 1
        scaleTarget = 1.12
        energy = max(energy, 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.scaleTarget = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { self.tintTarget = 0 }
    }

    func step(_ t: Double) {
        let dt = min(0.05, max(0, t - (last ?? t)))
        last = t
        let k = 1 - pow(0.02, dt)
        voiceBoost *= pow(0.08, dt)
        let target = min(1, energyTarget + voiceBoost * 0.7)
        energy += (target - energy) * k
        speed += (speedTarget - speed) * k
        tintAmount += (tintTarget - tintAmount) * (1 - pow(0.15, dt))
        scale += (scaleTarget - scale) * (1 - pow(0.002, dt))
        phase += dt * speed
    }
}

/// The living, iridescent 3D orb (ray-marched in Orb.metal).
struct OrbView: View {
    let engine: OrbEngine
    var paused: Bool = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: paused || reduceMotion)) { context in
            let _ = engine.step(context.date.timeIntervalSinceReferenceDate)
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.white)
                    .colorEffect(ShaderLibrary.orb(
                        .float2(Float(geo.size.width), Float(geo.size.height)),
                        .float(Float(engine.phase)),
                        .float(Float(engine.energy)),
                        .float3(engine.tint.x, engine.tint.y, engine.tint.z),
                        .float(Float(engine.tintAmount)),
                        .float2(engine.tilt.x, engine.tilt.y),
                        .float(scheme == .dark ? Float(1) : Float(0))
                    ))
                    .scaleEffect(engine.scale)
            }
        }
        .accessibilityHidden(true)
    }
}
