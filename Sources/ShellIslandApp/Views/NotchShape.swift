import SwiftUI

/// 刘海形状：顶部两侧内凹曲线（与物理刘海边缘吻合），底部两侧外凸圆角。
/// 与 macOS Dynamic Island 外观一致。
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let topR = min(topCornerRadius, rect.width / 4, rect.height / 4)
        let botR = min(bottomCornerRadius, rect.width / 4, rect.height / 2)

        var path = Path()

        // 从左上角开始
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // 左上内凹曲线
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
            control: CGPoint(x: rect.minX + topR, y: rect.minY)
        )

        // 左侧边缘到底部左圆角起点
        path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - botR))

        // 底部左圆角
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR + botR, y: rect.maxY),
            control: CGPoint(x: rect.minX + topR, y: rect.maxY)
        )

        // 底部边缘
        path.addLine(to: CGPoint(x: rect.maxX - topR - botR, y: rect.maxY))

        // 底部右圆角
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR),
            control: CGPoint(x: rect.maxX - topR, y: rect.maxY)
        )

        // 右侧边缘到右上内凹曲线
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))

        // 右上内凹曲线
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topR, y: rect.minY)
        )

        // 回到起点
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

extension NotchShape {
    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 20
    static let openedTopRadius: CGFloat = 22
    static let openedBottomRadius: CGFloat = 36

    static var closed: NotchShape {
        NotchShape(topCornerRadius: closedTopRadius, bottomCornerRadius: closedBottomRadius)
    }

    static var opened: NotchShape {
        NotchShape(topCornerRadius: openedTopRadius, bottomCornerRadius: openedBottomRadius)
    }
}