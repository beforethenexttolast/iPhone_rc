import SwiftUI

struct VideoSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.055),
                    Color(red: 0.07, green: 0.095, blue: 0.1),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color.cyan.opacity(0.16),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 520
            )

            ScanlineTexture()
                .opacity(0.24)

            VStack(spacing: 6) {
                Text("NO VIDEO")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .tracking(8)
                    .foregroundStyle(.white.opacity(0.18))
                Text("APFPV RTP / H.265 PIPELINE STUBBED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.16))
            }
        }
        .ignoresSafeArea()
    }
}

private struct ScanlineTexture: View {
    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                    context.fill(Path(rect), with: .color(.white.opacity(0.08)))
                    y += 4
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

