import SwiftUI

struct PixelMatrixView: View {
    let pattern: [String]
    let color: Color
    let pixelSize: CGFloat
    let spacing: CGFloat

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(pattern.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, pixel in
                        Rectangle()
                            .fill(pixel == Character("1") ? color : Color.clear)
                            .frame(width: pixelSize, height: pixelSize)
                    }
                }
            }
        }
        .drawingGroup(opaque: false)
    }
}

