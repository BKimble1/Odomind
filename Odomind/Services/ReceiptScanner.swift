import Foundation
import Vision
import UIKit
import OdomindCore

/// What on-device text recognition thought it saw on a receipt.
///
/// Every field is a *candidate*. Nothing here is saved without the owner
/// looking at it, and nothing here is described as verified. In particular,
/// none of this says anything about which car parts were bought: the text on a
/// receipt is text, and reading "oil filter" off it is not confirmation that an
/// oil filter that fits this vehicle was fitted to it.
struct ReceiptReading: Equatable {
    var merchant: String?
    var date: Date?
    var total: Decimal?
    var currencyCode: String?
    /// Every line recognised, so the review screen can show what it read
    /// rather than only what it guessed.
    var lines: [String]

    var isEmpty: Bool { merchant == nil && date == nil && total == nil }
}

/// Reads a receipt photo, on the device.
///
/// `VNRecognizeTextRequest` runs locally — no image, no text and no total
/// leaves the phone. That is the only reason this feature is acceptable at
/// all: a receipt carries a card's last four digits and a person's movements.
enum ReceiptScanner {
    enum ScanError: Error, LocalizedError {
        case notAnImage
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAnImage:
                return "That file is not an image Odomind can read."
            case .recognitionFailed(let detail):
                return "Odomind could not read that receipt: \(detail)"
            }
        }
    }

    /// Recognises text and pulls out the three fields worth pre-filling.
    ///
    /// Runs off the main actor: OCR on a 2,000-pixel image is not something to
    /// do on the thread drawing the screen.
    static func read(imageData: Data, calendar: Calendar = .current, now: Date = Date()) async throws -> ReceiptReading {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw ScanError.notAnImage
        }

        let lines: [String] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: ScanError.recognitionFailed(error.localizedDescription))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: observations.compactMap { $0.topCandidates(1).first?.string })
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: ScanError.recognitionFailed(error.localizedDescription))
                }
            }
        }

        return interpret(lines: lines, calendar: calendar, now: now)
    }

    /// The parsing, separated from the OCR so it can be tested against fixed
    /// text without an image or a simulator.
    static func interpret(lines: [String], calendar: Calendar = .current, now: Date = Date()) -> ReceiptReading {
        ReceiptReading(
            merchant: merchant(in: lines),
            date: date(in: lines, calendar: calendar, now: now),
            total: total(in: lines),
            currencyCode: Locale.current.currency?.identifier,
            lines: lines
        )
    }

    /// The first line that reads like a business name.
    ///
    /// Receipts put the shop at the top. Lines that are mostly digits,
    /// punctuation or a single word like "RECEIPT" are skipped.
    private static func merchant(in lines: [String]) -> String? {
        for line in lines.prefix(6) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3, trimmed.count <= 40 else { continue }
            let letters = trimmed.filter { $0.isLetter }.count
            guard letters >= trimmed.count / 2 else { continue }
            let ignored = ["receipt", "invoice", "customer copy", "thank you", "merchant copy"]
            guard !ignored.contains(where: { trimmed.lowercased().contains($0) }) else { continue }
            return trimmed
        }
        return nil
    }

    /// The most plausible date on the receipt.
    ///
    /// A future date is rejected outright — a receipt cannot be for work that
    /// has not happened — and so is anything more than ten years old, which is
    /// almost always a misread part number.
    private static func date(in lines: [String], calendar: Calendar, now: Date) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        guard let detector else { return nil }

        let earliest = calendar.date(byAdding: .year, value: -10, to: now) ?? now
        var best: Date?
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            detector.enumerateMatches(in: line, range: range) { match, _, _ in
                guard let found = match?.date else { return }
                guard found <= now, found >= earliest else { return }
                // The latest plausible date wins: receipts carry expiry and
                // "member since" dates that are older than the transaction.
                if best == nil || found > (best ?? found) { best = found }
            }
        }
        return best
    }

    /// The amount beside the word "total", or the largest amount on the
    /// receipt if there is no such line.
    private static func total(in lines: [String]) -> Decimal? {
        let amountPattern = #"[0-9]+[.,][0-9]{2}"#

        func amounts(in line: String) -> [Decimal] {
            var found: [Decimal] = []
            var search = line[...]
            while let range = search.range(of: amountPattern, options: .regularExpression) {
                let text = search[range].replacingOccurrences(of: ",", with: ".")
                if let value = Decimal(string: text) { found.append(value) }
                search = search[range.upperBound...]
            }
            return found
        }

        // A line saying "total" is a far better signal than the biggest
        // number, which is often a phone number or a card number.
        for line in lines {
            let lowered = line.lowercased()
            guard lowered.contains("total") else { continue }
            guard !lowered.contains("subtotal") else { continue }
            if let value = amounts(in: line).max() { return value }
        }
        return lines.flatMap(amounts).max()
    }
}
