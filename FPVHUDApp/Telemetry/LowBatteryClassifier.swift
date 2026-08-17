import Foundation

// Low-battery banner model, in parity with the ground-station laptop HUD
// (`w17-ground-station/shared/lowBattery.mjs`): same thresholds, same hysteresis,
// same one-level-at-a-time exit, same wording family — so both screens always
// tell the same story from the same `battery_v` value.
//
// Display only: this classifies a voltage for a banner and a tint. It commands
// nothing; the firmware's warning-only battery invariant is untouched, and no
// contract/schema field is involved.

enum LowBatteryLevel: String, Equatable {
    case ok
    case warn
    case critical

    /// Exact ground-station wording (`LOW_BATTERY_LABELS`). Plain language by
    /// requirement: what happened + what to do; the BAT metric next to the
    /// banner already shows the number.
    var bannerText: String? {
        switch self {
        case .ok: return nil
        case .warn: return "BATTERY LOW — finish your lap and park"
        case .critical: return "BATTERY CRITICAL — park the car now"
        }
    }
}

struct LowBatteryThresholds: Equatable {
    /// Thresholds are PACK volts (what `battery_v` carries), not per-cell:
    /// defaults assume the W17's 2S LiPo — warn at 3.5 V/cell = 7.0 V pack,
    /// critical at 3.3 V/cell = 6.6 V pack (ground-station defaults).
    static let defaultWarnVolts = 7.0
    static let defaultCriticalVolts = 6.6

    /// A level is entered the instant the voltage touches its threshold (never
    /// late — it is a safety cue) but exits only after recovering this far above
    /// it, because a LiPo sags under throttle and recovers at idle.
    static let hysteresisVolts = 0.15

    /// Sanity band for injected thresholds (volts). Wide on purpose — pack volts
    /// for any plausible battery — while rejecting the classic unit mistakes
    /// (zero, negative, millivolts). Out-of-band or non-finite values repair to
    /// the defaults field-by-field, matching `normalizeLowBatterySettings`.
    static let sanityBandVolts = 1.0...60.0

    static let defaults = LowBatteryThresholds()

    let warnVolts: Double
    let criticalVolts: Double

    init(
        warnVolts: Double = LowBatteryThresholds.defaultWarnVolts,
        criticalVolts: Double = LowBatteryThresholds.defaultCriticalVolts
    ) {
        let warn = Self.sanitized(warnVolts) ?? Self.defaultWarnVolts
        var critical = Self.sanitized(criticalVolts) ?? Self.defaultCriticalVolts
        // Critical may never sit above warn (the banner would jump straight to
        // CRITICAL with no warning stage); repair by lowering critical to warn.
        if critical > warn {
            critical = warn
        }
        self.warnVolts = warn
        self.criticalVolts = critical
    }

    private static func sanitized(_ value: Double) -> Double? {
        guard value.isFinite, sanityBandVolts.contains(value) else { return nil }
        return value
    }
}

struct LowBatteryClassifier: Equatable {
    let thresholds: LowBatteryThresholds
    private(set) var level: LowBatteryLevel = .ok

    init(thresholds: LowBatteryThresholds = .defaults) {
        self.thresholds = thresholds
    }

    /// One pure classification step (ground-station `lowBatteryLevel` parity):
    ///
    ///   enter:  v <= criticalVolts            -> critical   (immediate, never late)
    ///           v <= warnVolts                -> warn
    ///   exit:   only after recovering `hysteresisVolts` above the level's own
    ///           threshold, and only one level at a time — the final
    ///           previous == .critical ratchet makes that literal: even a single
    ///           reading recovering past warn + hysteresis steps critical down
    ///           to warn for one classification and lets warn's own exit run on
    ///           the next, so the banner never blinks straight off.
    ///
    /// A reading that is not a finite number returns `.ok` — no reading, no
    /// claim. Deliberately no coercion: a live telemetry field is a number or
    /// it is nothing.
    static func step(
        previous: LowBatteryLevel,
        packVoltage voltage: Double,
        thresholds: LowBatteryThresholds = .defaults
    ) -> LowBatteryLevel {
        guard voltage.isFinite else { return .ok }
        let hysteresis = LowBatteryThresholds.hysteresisVolts
        if voltage <= thresholds.criticalVolts { return .critical }
        if previous == .critical && voltage < thresholds.criticalVolts + hysteresis { return .critical }
        if voltage <= thresholds.warnVolts { return .warn }
        if (previous == .warn || previous == .critical) && voltage < thresholds.warnVolts + hysteresis { return .warn }
        if previous == .critical { return .warn } // ratchet: critical never exits straight to ok
        return .ok
    }

    @discardableResult
    mutating func classify(packVoltage voltage: Double) -> LowBatteryLevel {
        level = Self.step(previous: level, packVoltage: voltage, thresholds: thresholds)
        return level
    }

    mutating func reset() {
        level = .ok
    }

    /// One display-refresh step, applying the HUD freshness gating:
    ///
    /// - live values classify normally;
    /// - the stale display tier (1–3 s) HOLDS the last level — an aging value
    ///   makes no new claim, and the banner dims to match the degraded-value
    ///   presentation instead of flapping off and on across short gaps;
    /// - a Windows-flagged stale battery value (`stale_data_warnings: battery`)
    ///   also holds, for the same reason;
    /// - lost/placeholder telemetry CLEARS to `.ok`: the HUD clears the battery
    ///   number to `--.- V`, so a banner claiming to know the pack state would
    ///   lie. Re-entry after recovery is immediate because entry is never late.
    @discardableResult
    mutating func update(
        packVoltage voltage: Double?,
        showsLiveValues: Bool,
        freshness: TelemetryFreshness,
        batteryFlaggedStale: Bool
    ) -> LowBatteryLevel {
        guard showsLiveValues, freshness != .dataLost else {
            reset()
            return level
        }
        guard freshness == .live, !batteryFlaggedStale else {
            return level
        }
        return classify(packVoltage: voltage ?? .nan)
    }
}
