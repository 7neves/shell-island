import SwiftUI

struct PixelWordView: View {
    let word: String
    let color: Color

    var body: some View {
        HStack(spacing: 1.2) {
            ForEach(Array(word.enumerated()), id: \.offset) { _, character in
                PixelLetterView(letter: character, color: color)
            }
        }
    }
}

private struct PixelLetterView: View {
    let letter: Character
    let color: Color

    var body: some View {
        let pattern = Self.patterns[letter] ?? Self.patterns["C"]!
        PixelMatrixView(pattern: pattern, color: color, pixelSize: 1.1, spacing: 0.35)
    }

    private static let patterns: [Character: [String]] = [
        "C": ["111", "100", "100", "100", "111"],
        "P": ["110", "101", "110", "100", "100"],
        "U": ["101", "101", "101", "101", "111"],
        "M": ["101", "111", "111", "101", "101"],
        "E": ["111", "100", "110", "100", "111"]
    ]
}

