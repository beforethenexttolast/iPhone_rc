import SwiftUI

enum HUDPalette {
    static let teal = Color(red: 0.0, green: 0.82, blue: 0.75)
    static let tealBright = Color(red: 0.15, green: 0.96, blue: 0.87)
    static let green = Color(red: 0.0, green: 0.9, blue: 0.45)
    static let red = Color(red: 1.0, green: 0.12, blue: 0.12)
    static let amber = Color(red: 1.0, green: 0.68, blue: 0.08)
    static let panel = Color.black.opacity(0.64)
    static let panelStrong = Color.black.opacity(0.78)
    static let edge = teal.opacity(0.38)
    static let muted = Color.white.opacity(0.58)
}

struct HUDPanel<Content: View>: View {
    var prominence: Prominence = .normal
    private let content: Content

    enum Prominence {
        case normal
        case strong
    }

    init(prominence: Prominence = .normal, @ViewBuilder content: () -> Content) {
        self.prominence = prominence
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(prominence == .strong ? HUDPalette.panelStrong : HUDPalette.panel)
            .overlay(
                ChamferedRectangle(cut: 10)
                    .stroke(HUDPalette.edge, lineWidth: 1)
            )
            .clipShape(ChamferedRectangle(cut: 10))
            .shadow(color: .black.opacity(0.42), radius: 12, x: 0, y: 4)
    }
}

struct ChamferedRectangle: Shape {
    var cut: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let c = min(cut, rect.width / 3, rect.height / 3)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        path.closeSubpath()
        return path
    }
}

struct HUDIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(configuration.isPressed ? HUDPalette.panelStrong : HUDPalette.panel)
            .overlay(
                ChamferedRectangle(cut: 8)
                    .stroke(HUDPalette.edge, lineWidth: 1)
            )
            .clipShape(ChamferedRectangle(cut: 8))
    }
}

struct StatusMetric: View {
    var title: String
    var value: String
    var alignment: HorizontalAlignment = .leading
    var tint: Color = .white

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title)
                .hudLabel()
            Text(value)
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
    }
}

struct StatusPill: View {
    var text: String
    var tint: Color
    var compact = false

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 10 : 11, weight: .black, design: .monospaced))
            .tracking(compact ? 1.0 : 1.4)
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .padding(.horizontal, compact ? 7 : 10)
            .padding(.vertical, compact ? 5 : 7)
            .background(tint.opacity(0.9))
            .foregroundStyle(.black)
            .clipShape(ChamferedRectangle(cut: 6))
    }
}

struct RecordingIndicator: View {
    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(HUDPalette.red)
                .frame(width: 8, height: 8)
                .shadow(color: HUDPalette.red.opacity(0.8), radius: 5)
            Text("REC STBY")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .tracking(1.4)
        }
        .foregroundStyle(.white.opacity(0.92))
    }
}

struct MeterBar: View {
    var title: String
    var value: Double
    var tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Text(title)
                .hudLabel()
                .frame(width: 34, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    ChamferedRectangle(cut: 4)
                        .fill(.white.opacity(0.11))
                    ChamferedRectangle(cut: 4)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.72), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, proxy.size.width * min(max(value, 0), 1)))
                        .shadow(color: tint.opacity(0.45), radius: 7)
                }
            }
            .frame(height: 12)
        }
    }
}

struct SteeringBar: View {
    var value: Double

    var body: some View {
        HStack(spacing: 9) {
            Text("STR")
                .hudLabel()
                .frame(width: 34, alignment: .leading)
            GeometryReader { proxy in
                let clamped = min(max(value, -1), 1)
                let x = proxy.size.width * CGFloat((clamped + 1) / 2)

                ZStack(alignment: .leading) {
                    ChamferedRectangle(cut: 4)
                        .fill(.white.opacity(0.11))
                    Rectangle()
                        .fill(.white.opacity(0.32))
                        .frame(width: 1)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    ChamferedRectangle(cut: 4)
                        .fill(HUDPalette.tealBright)
                        .frame(width: 20, height: 14)
                        .position(x: x, y: proxy.size.height / 2)
                        .shadow(color: HUDPalette.teal.opacity(0.75), radius: 8)
                }
            }
            .frame(height: 14)
        }
    }
}

struct VerticalSignalBar: View {
    var title: String
    var value: Double
    var tint: Color

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let clamped = min(max(value, 0), 1)
                ZStack(alignment: .bottom) {
                    ChamferedRectangle(cut: 4)
                        .fill(.white.opacity(0.1))
                    ChamferedRectangle(cut: 4)
                        .fill(tint)
                        .frame(height: proxy.size.height * clamped)
                }
            }
            .frame(width: 18, height: 72)
            Text(title)
                .hudLabel()
                .frame(width: 48)
        }
    }
}

extension Text {
    func hudLabel() -> some View {
        self
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(HUDPalette.muted)
    }
}

