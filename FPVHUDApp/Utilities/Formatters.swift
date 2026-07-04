import Foundation

extension Double {
    var radiansToDegrees: Double {
        self * 180.0 / .pi
    }
}

enum HUDFormatters {
    static func signedDegrees(_ value: Double) -> String {
        String(format: "%+.1f°", value)
    }

    static func volts(_ value: Double) -> String {
        String(format: "%.2f V", value)
    }

    static func db(_ value: Double) -> String {
        String(format: "%.1f dB", value)
    }
}

