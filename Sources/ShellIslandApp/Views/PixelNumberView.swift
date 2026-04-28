import SwiftUI

struct PixelNumberView: View {
    let number: Int
    let color: Color

    var body: some View {
        let digits = Array(String(max(0, min(number, 99))))

        HStack(spacing: 3) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                PixelDigitView(digit: digit, color: color, pixelSize: 1.96, spacing: 0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PixelTinyNumberView: View {
    let number: Int
    let color: Color

    var body: some View {
        let digits = Array(String(max(0, min(number, 99))))

        HStack(spacing: 2) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                PixelDigitView(digit: digit, color: color, pixelSize: 1.25, spacing: 0.45)
            }
        }
    }
}

private struct PixelDigitView: View {
    let digit: Character
    let color: Color
    let pixelSize: CGFloat
    let spacing: CGFloat

    var body: some View {
        let pattern = Self.patterns[digit] ?? Self.patterns["0"]!
        PixelMatrixView(pattern: pattern, color: color, pixelSize: pixelSize, spacing: spacing)
    }

    private static let patterns: [Character: [String]] = [
        "0": ["111", "101", "101", "101", "111"],
        "1": ["010", "110", "010", "010", "111"],
        "2": ["111", "001", "111", "100", "111"],
        "3": ["111", "001", "111", "001", "111"],
        "4": ["101", "101", "111", "001", "001"],
        "5": ["111", "100", "111", "001", "111"],
        "6": ["111", "100", "111", "101", "111"],
        "7": ["111", "001", "001", "001", "001"],
        "8": ["111", "101", "111", "101", "111"],
        "9": ["111", "101", "111", "001", "111"]
    ]
}

