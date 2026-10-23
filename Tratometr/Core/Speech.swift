import Foundation
import Speech
import AVFoundation
import CoreMotion
import SwiftUI

/// Live Russian speech recognition. Stops on its own after a short pause.
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRunning = false
    @Published var level: Double = 0
    @Published var errorText: String?
    /// Increments every time a recording session ends (pause, manual stop or limit).
    @Published var finishedCount = 0

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceWork: DispatchWorkItem?

    func start() {
        guard !isRunning else { return }
        errorText = nil
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.errorText = "Разреши распознавание речи: Настройки iPhone → Тратометр."
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self.errorText = "Разреши доступ к микрофону: Настройки iPhone → Тратометр."
                            return
                        }
                        self.begin()
                    }
                }
            }
        }
    }

    func stop() { finish() }

    private func begin() {
        guard !isRunning else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorText = "Распознавание речи сейчас недоступно. Проверь интернет или напиши текстом."
            return
        }
        task?.cancel()
        task = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorText = "Не получилось включить микрофон."
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        req.taskHint = .dictation
        req.contextualStrings = ["рублей", "евро", "долларов", "такси", "кофе", "капучино", "Пятёрочка",
                                 "Перекрёсток", "ВкусВилл", "Wildberries", "Ozon", "полторы тысячи", "вчера", "позавчера"]
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorText = "Микрофон сейчас занят другим приложением."
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            let lvl = audioLevel(buffer)
            DispatchQueue.main.async { self?.level = lvl }
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            errorText = "Не получилось включить микрофон."
            return
        }

        transcript = ""
        isRunning = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal { self.finish() } else { self.armSilence(1.7) }
                } else if error != nil {
                    self.finish()
                }
            }
        }
        armSilence(8)
    }

    private func armSilence(_ seconds: Double) {
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func finish() {
        guard isRunning else { return }
        silenceWork?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRunning = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        finishedCount += 1
    }
}

private func audioLevel(_ buffer: AVAudioPCMBuffer) -> Double {
    guard let ch = buffer.floatChannelData?[0] else { return 0 }
    let n = Int(buffer.frameLength)
    guard n > 0 else { return 0 }
    var sum: Float = 0
    for i in 0..<n { sum += ch[i] * ch[i] }
    let rms = sqrt(sum / Float(n))
    let db = 20 * log10(max(rms, 0.000_01))
    return Double(max(0, min(1, (db + 50) / 40)))
}

/// Gyroscope tilt used for the parallax on the card and the light on the orb.
final class MotionManager: ObservableObject {
    @Published var tilt: CGSize = .zero
    var onTilt: ((CGSize) -> Void)?
    private let manager = CMMotionManager()
    private var base: (pitch: Double, roll: Double)?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.attitude else { return }
            var b = self.base ?? (pitch: a.pitch, roll: a.roll)
            // the "rest" position slowly follows how the phone is held
            b.pitch += (a.pitch - b.pitch) * 0.02
            b.roll += (a.roll - b.roll) * 0.02
            self.base = b
            let x = max(-0.35, min(0.35, a.roll - b.roll))
            let y = max(-0.35, min(0.35, a.pitch - b.pitch))
            let t = CGSize(width: x, height: y)
            self.tilt = t
            self.onTilt?(t)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        base = nil
    }
}
