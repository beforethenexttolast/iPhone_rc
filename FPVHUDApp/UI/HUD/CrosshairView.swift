import SwiftUI

struct CrosshairView: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let radius = size * 0.25
                let outer = size * 0.46
                let innerGap = size * 0.09
                let bracket = size * 0.14

                var glow = Path()
                glow.addEllipse(in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.stroke(glow, with: .color(HUDPalette.teal.opacity(0.24)), lineWidth: 8)

                var path = Path()
                path.addEllipse(in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))

                path.move(to: CGPoint(x: center.x - outer, y: center.y))
                path.addLine(to: CGPoint(x: center.x - innerGap, y: center.y))
                path.move(to: CGPoint(x: center.x + innerGap, y: center.y))
                path.addLine(to: CGPoint(x: center.x + outer, y: center.y))
                path.move(to: CGPoint(x: center.x, y: center.y - outer))
                path.addLine(to: CGPoint(x: center.x, y: center.y - innerGap))
                path.move(to: CGPoint(x: center.x, y: center.y + innerGap))
                path.addLine(to: CGPoint(x: center.x, y: center.y + outer))

                addCornerBracket(to: &path, center: center, x: -outer, y: -outer, bracket: bracket)
                addCornerBracket(to: &path, center: center, x: outer, y: -outer, bracket: bracket)
                addCornerBracket(to: &path, center: center, x: -outer, y: outer, bracket: bracket)
                addCornerBracket(to: &path, center: center, x: outer, y: outer, bracket: bracket)

                context.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 1.5)

                var dot = Path()
                dot.addEllipse(in: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5))
                context.fill(dot, with: .color(HUDPalette.tealBright))

                var horizon = Path()
                horizon.move(to: CGPoint(x: center.x - radius * 0.7, y: center.y + radius * 0.56))
                horizon.addLine(to: CGPoint(x: center.x + radius * 0.7, y: center.y + radius * 0.56))
                context.stroke(horizon, with: .color(HUDPalette.tealBright.opacity(0.65)), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.92), radius: 3)
    }

    private func addCornerBracket(to path: inout Path, center: CGPoint, x: CGFloat, y: CGFloat, bracket: CGFloat) {
        let xSign: CGFloat = x < 0 ? 1 : -1
        let ySign: CGFloat = y < 0 ? 1 : -1
        let corner = CGPoint(x: center.x + x, y: center.y + y)

        path.move(to: corner)
        path.addLine(to: CGPoint(x: corner.x + bracket * xSign, y: corner.y))
        path.move(to: corner)
        path.addLine(to: CGPoint(x: corner.x, y: corner.y + bracket * ySign))
    }
}

