import SwiftUI

enum ComposeStart: String, Identifiable {
    case voice, text, scan, gallery
    var id: String { rawValue }
}

enum AppTab {
    case home, balance, stats, history
}

struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    let undo: (() -> Void)?
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
}

final class AppState: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var compose: ComposeStart?
    @Published var showSettings = false
    @Published var toast: ToastMessage?
    @Published var mood: OrbMood = .idle
    /// Record opened in the one-tap category picker
    @Published var quickFix: Expense?

    let orb = OrbEngine()
    let speech = SpeechRecognizer()
    let motion = MotionManager()

    init() {
        motion.onTilt = { [weak self] v in
            self?.orb.tilt = SIMD2<Float>(Float(v.width), Float(v.height))
        }
    }

    func setMood(_ m: OrbMood) {
        mood = m
        orb.apply(m)
    }

    func go(_ t: AppTab) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { tab = t }
    }

    func showToast(_ text: String, undo: (() -> Void)? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        let message = ToastMessage(text: text, undo: undo, actionTitle: actionTitle, action: action)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { toast = message }
        let seconds: Double = (undo == nil && action == nil) ? 3.2 : 7
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.toast?.id == message.id else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.toast = nil }
        }
    }
}
