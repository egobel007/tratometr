import Foundation
import UIKit
import Vision
import VisionKit
import SwiftUI

/// Reads receipt text on the device (no internet needed) and finds the total.
enum ReceiptOCR {
    static func recognize(_ image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        let orientation = Self.orientation(image.imageOrientation)
        return await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var done = false
                let request = VNRecognizeTextRequest { req, _ in
                    let lines = (req.results as? [VNRecognizedTextObservation])?
                        .compactMap { $0.topCandidates(1).first?.string } ?? []
                    if !done { done = true; cont.resume(returning: lines) }
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["ru-RU", "en-US", "de-DE"]
                let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
                do { try handler.perform([request]) } catch {
                    if !done { done = true; cont.resume(returning: []) }
                }
            }
        }
    }

    static func extract(lines: [String], currency: String) -> [DraftExpense] {
        let lower = lines.map { $0.lowercased().replacingOccurrences(of: "ё", with: "е") }
        let keys = ["к оплате", "итого", "итог", "всего", "сумма", "оплачено", "безналичн", "total", "totaal", "betalen", "summe"]
        var candidates: [Double] = []
        for (i, line) in lower.enumerated() where keys.contains(where: { line.contains($0) }) {
            if let v = amount(in: line) { candidates.append(v) }
            else if i + 1 < lower.count, let v = amount(in: lower[i + 1]) { candidates.append(v) }
        }
        var total = candidates.max()
        if total == nil { total = lower.compactMap { decimalAmount(in: $0) }.max() }
        guard let sum = total, sum > 0 else { return [] }

        let skip = ["кассов", "чек", "инн", "ккт", "фн", "смена", "добро пожаловать", "receipt"]
        let merchant = lines.prefix(5).first { l in
            let low = l.lowercased()
            return l.filter(\.isLetter).count >= 3 && !skip.contains(where: { low.contains($0) })
        }?.trimmingCharacters(in: CharacterSet(charactersIn: " *\"«»"))

        let whole = lower.joined(separator: " ")
        var cat = LocalParser.detectCategory((merchant ?? "").lowercased())
        if cat == .other { cat = LocalParser.detectCategory(whole) }

        var date = Date()
        if let g = whole.captureGroups(#"(\d{2})[./](\d{2})[./](\d{2,4})"#),
           let d = Int(g[1]), let m = Int(g[2]), var y = Int(g[3]) {
            if y < 100 { y += 2000 }
            var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = d; comps.hour = 12
            if let parsed = RuDate.cal.date(from: comps), parsed <= Date(),
               parsed > Date().addingTimeInterval(-90 * 86400) {
                date = parsed
            }
        }

        let note = merchant.map { String($0.prefix(40)) } ?? "Покупка по чеку"
        return [DraftExpense(amount: sum, currency: currency, category: cat, note: note,
                             date: date, source: "photo", raw: lines.joined(separator: "\n"))]
    }

    /// "итого =1 234,56" -> 1234.56
    static func amount(in line: String) -> Double? {
        if let d = decimalAmount(in: line) { return d }
        let norm = line.replacingRegex(#"(\d)[\s ](?=\d{3}(?!\d))"#, with: "$1")
        let ints = norm.allCaptureGroups(#"(?<![\d.,])(\d{1,7})(?![\d.,])"#).compactMap { Double($0[1]) }
        return ints.filter { $0 > 0 }.max()
    }

    static func decimalAmount(in line: String) -> Double? {
        let norm = line.replacingRegex(#"(\d)[\s ](?=\d{3}[.,]\d{2}(?!\d))"#, with: "$1")
        let vals = norm.allCaptureGroups(#"(\d{1,7})[.,](\d{2})(?!\d)"#).compactMap { Double("\($0[1]).\($0[2])") }
        return vals.filter { $0 > 0 }.max()
    }
}

extension ReceiptOCR {
    static func orientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

/// System document camera: finds the receipt edges and flattens it.
struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish(scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(nil)
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish(nil)
        }
    }
}
