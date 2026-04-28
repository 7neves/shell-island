import SwiftUI
import ShellIslandCore

struct PixelTaskAnimationView: View {
    let kind: TaskKind?
    let isActive: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.24)) { timeline in
            let tick = Int(timeline.date.timeIntervalSinceReferenceDate * 4)
            let frames = framesForCurrentKind
            let frame = frames[tick % frames.count]

            PixelMatrixView(pattern: frame, color: color, pixelSize: 1.96, spacing: 0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var framesForCurrentKind: [[String]] {
        switch kind {
        case .brew:
            return Self.brewFrames
        case .claudeCode:
            return Self.claudeCodeFrames
        case .npmRun:
            return Self.npmFrames
        case .pnpmRun:
            return Self.npmFrames
        case .yarnRun:
            return Self.npmFrames
        case .none:
            return isActive ? Self.idleActiveFrames : Self.idleFrames
        }
    }

    private static let idleFrames: [[String]] = [
        [
            // Geek idle (stable): `>_` prompt, cursor on
            "00000000",
            "00000000",
            "00100000",
            "00010000",
            "00100000",
            "00000000",
            "00111000",
            "00000000"
        ],
        [
            // cursor on (hold)
            "00000000",
            "00000000",
            "00100000",
            "00010000",
            "00100000",
            "00000000",
            "00111000",
            "00000000"
        ],
        [
            // cursor on (hold)
            "00000000",
            "00000000",
            "00100000",
            "00010000",
            "00100000",
            "00000000",
            "00111000",
            "00000000"
        ],
        [
            // cursor off (blink)
            "00000000",
            "00000000",
            "00100000",
            "00010000",
            "00100000",
            "00000000",
            "00000000",
            "00000000"
        ]
    ]

    private static let idleActiveFrames: [[String]] = [
        [
            "10000001",
            "01000010",
            "00100100",
            "00011000",
            "00100100",
            "01000010",
            "10000001",
            "00000000"
        ],
        [
            "00000000",
            "10000001",
            "01000010",
            "00100100",
            "00011000",
            "00100100",
            "01000010",
            "10000001"
        ]
    ]

    private static let claudeCodeFrames: [[String]] = [
        [
            // Diamond expanding: outer ring
            "00010000",
            "00101000",
            "01000100",
            "10000010",
            "01000100",
            "00101000",
            "00010000",
            "00000000"
        ],
        [
            // Diamond contracting: inner ring
            "00000000",
            "00010000",
            "00101000",
            "01000100",
            "00101000",
            "00010000",
            "00000000",
            "00000000"
        ]
    ]

    private static let npmFrames: [[String]] = [
        [
            "00011000",
            "00111100",
            "01111110",
            "11100111",
            "11100111",
            "01111110",
            "00111100",
            "00011000"
        ],
        [
            "00011000",
            "00111100",
            "01101110",
            "11001111",
            "11110011",
            "01110110",
            "00111100",
            "00011000"
        ]
    ]

    private static let brewFrames: [[String]] = [
        [
            "00100100",
            "00010000",
            "01111100",
            "01000110",
            "01111110",
            "00111100",
            "00000000",
            "00011000"
        ],
        [
            "00010000",
            "00100100",
            "01111100",
            "01000110",
            "01111110",
            "00111100",
            "00011000",
            "00000000"
        ]
    ]
}

