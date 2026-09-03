import Foundation
import SwiftUI

// MARK: - Medication form

enum MedicationForm: Int16, CaseIterable, Identifiable {
    case tablet = 0
    case liquid = 1
    case drops = 2
    case suppository = 3
    case spray = 4
    case injection = 5
    case other = 6

    var id: Int16 { rawValue }

    var symbolName: String {
        switch self {
        case .tablet: return "pills.fill"
        case .liquid: return "waterbottle.fill"
        case .drops: return "drop.fill"
        case .suppository: return "capsule.fill"
        case .spray: return "aqi.medium"
        case .injection: return "syringe.fill"
        case .other: return "cross.case.fill"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .tablet: return "Tablet"
        case .liquid: return "Liquid"
        case .drops: return "Drops"
        case .suppository: return "Suppository"
        case .spray: return "Spray"
        case .injection: return "Injection"
        case .other: return "Other"
        }
    }

    /// Unit that is offered first when this form is picked.
    var defaultUnit: String {
        switch self {
        case .tablet: return "pc"
        case .liquid: return "ml"
        case .drops: return "drops"
        case .suppository: return "pc"
        case .spray: return "puff"
        case .injection: return "ml"
        case .other: return "mg"
        }
    }
}

/// Units offered in the dose editor. Stored as a plain string so anything can be typed later.
enum DoseUnit {
    static let suggestions = ["mg", "ml", "pc", "drops", "puff", "µg", "IU"]

    static func label(for raw: String) -> LocalizedStringKey {
        switch raw {
        case "pc": return "pc"
        case "drops": return "drops"
        case "puff": return "puff"
        default: return LocalizedStringKey(raw)
        }
    }

    /// Same mapping as `label(for:)` but as a plain `String`, for the places
    /// that build a sentence rather than a view — dose summaries and
    /// notification bodies. Units like mg or ml are the same in every language
    /// and pass through untouched.
    static func localizedName(for raw: String) -> String {
        switch raw {
        case "pc": return String(localized: "pc")
        case "drops": return String(localized: "drops")
        case "puff": return String(localized: "puff")
        default: return raw
        }
    }
}

// MARK: - Dose status

enum DoseStatus: Int16, CaseIterable, Identifiable {
    case given = 0
    case skipped = 1
    case refused = 2

    var id: Int16 { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .given: return "Given"
        case .skipped: return "Skipped"
        case .refused: return "Refused"
        }
    }

    var symbolName: String {
        switch self {
        case .given: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .refused: return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .given: return .green
        case .skipped: return .orange
        case .refused: return .red
        }
    }
}

// MARK: - Recurrence

enum Recurrence: Int16, CaseIterable, Identifiable {
    case daily = 0
    case everyNDays = 1
    case weekdays = 2

    var id: Int16 { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .daily: return "Every day"
        case .everyNDays: return "Every N days"
        case .weekdays: return "On certain weekdays"
        }
    }
}

// MARK: - Care events

enum EventCategory: Int16, CaseIterable, Identifiable {
    case fever = 0
    case sideEffect = 1
    case vomiting = 2
    case doctorVisit = 3
    case note = 4
    case bloodPressure = 5
    case bloodSugar = 6
    case seizure = 7

    var id: Int16 { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .fever: return "Fever"
        case .sideEffect: return "Side effect"
        case .vomiting: return "Vomiting"
        case .doctorVisit: return "Doctor visit"
        case .note: return "Note"
        case .bloodPressure: return "Blood pressure"
        case .bloodSugar: return "Blood sugar"
        case .seizure: return "Seizure"
        }
    }

    var symbolName: String {
        switch self {
        case .fever: return "thermometer.high"
        case .sideEffect: return "exclamationmark.triangle.fill"
        case .vomiting: return "arrow.up.heart.fill"
        case .doctorVisit: return "stethoscope"
        case .note: return "note.text"
        case .bloodPressure: return "heart.circle"
        case .bloodSugar: return "drop.circle"
        case .seizure: return "waveform.path.ecg"
        }
    }

    var tint: Color {
        switch self {
        case .fever: return .red
        case .sideEffect: return .orange
        case .vomiting: return .purple
        case .doctorVisit: return .blue
        case .note: return .secondary
        case .bloodPressure: return .pink
        case .bloodSugar: return .indigo
        case .seizure: return .yellow
        }
    }

    /// Categories that usually carry a measured value, and the unit to preselect.
    var suggestedUnit: String? {
        switch self {
        case .fever: return "°C"
        case .bloodPressure: return BloodPressure.unit
        case .bloodSugar: return BloodSugarUnit.mgPerDeciliter.rawValue
        case .seizure: return SeizureDuration.unit
        default: return nil
        }
    }

    /// What kind of number this category takes — one, two, or one out of a
    /// fixed pair of units. The editor, the list and the report all read this
    /// rather than each deciding for themselves.
    var measurementShape: MeasurementShape {
        switch self {
        case .bloodPressure: return .bloodPressure
        case .bloodSugar: return .bloodSugar
        case .seizure: return .seizure
        case .fever: return .single(defaultUnit: "°C")
        case .sideEffect, .vomiting, .doctorVisit, .note: return .single(defaultUnit: nil)
        }
    }

    /// Whether a fresh event of this kind should start with the value field
    /// open. Measuring is the whole point of these three.
    var startsWithMeasurement: Bool {
        switch self {
        case .fever, .bloodPressure, .bloodSugar, .seizure: return true
        default: return false
        }
    }
}

// MARK: - Day parts

/// Groups the slots of a day so the Today screen stays readable when many
/// medications are due.
enum DayPart: Int, CaseIterable, Identifiable {
    case morning = 0
    case midday = 1
    case evening = 2
    case night = 3

    var id: Int { rawValue }

    static func containing(minuteOfDay: Int) -> DayPart {
        switch minuteOfDay {
        case ..<(11 * 60): return .morning
        case ..<(17 * 60): return .midday
        case ..<(22 * 60): return .evening
        default: return .night
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .morning: return "Morning"
        case .midday: return "Midday"
        case .evening: return "Evening"
        case .night: return "Night"
        }
    }

    var symbolName: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .midday: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }
}

// MARK: - Time formatting

/// One time format across the whole app.
///
/// `.shortened` renders 08:00 as "8:00" in German while the schedule rows use
/// `.dateTime.hour().minute()` and render "08:00". Two formats side by side on
/// the same screen read as a bug, so everything goes through here.
enum TimeText {
    static func of(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}

// MARK: - Colors

/// Fixed palette so a colour picked on one device renders identically on another.
enum MedColor: String, CaseIterable, Identifiable {
    case blue = "007AFF"
    case teal = "30B0C7"
    case green = "34C759"
    case yellow = "FFCC00"
    case orange = "FF9500"
    case red = "FF3B30"
    case pink = "FF2D55"
    case purple = "AF52DE"

    var id: String { rawValue }
    var color: Color { Color(hex: rawValue) ?? .accentColor }
    static var fallback: MedColor { .blue }

}

// MARK: - Child colours

/// The colours a child's name is written in.
///
/// A separate palette from `MedColor` for two reasons, both learned from
/// looking at the running app:
///
/// - **No status colours.** Green, orange and red mean given, skipped and
///   refused, and red is what the duplicate-dose warning shouts in. A child
///   named in that red teaches people to stop noticing it.
/// - **Readable at caption size on white.** The child's name is set small and
///   uppercase above the row, so yellow is out.
enum ChildColor: String, CaseIterable, Identifiable {
    case blue = "007AFF"
    case teal = "30B0C7"
    case indigo = "5856D6"
    case purple = "AF52DE"
    case pink = "FF2D55"
    case brown = "A2845E"

    var id: String { rawValue }
    var color: Color { Color(hex: rawValue) ?? .accentColor }

    static var fallback: ChildColor { .blue }

    /// Picks a colour no sibling is using yet.
    ///
    /// Assigned once, at creation, and stored on the record — so it is the same
    /// on every iPhone sharing the plan, and two children cannot collide. An
    /// earlier version derived it from the child's UUID instead, which looked
    /// tidier and was wrong: with six colours, two siblings landed on the same
    /// one often enough to make the labelling useless exactly when it matters.
    ///
    /// Beyond `allCases.count` children the palette repeats — by then the names
    /// are doing the work anyway.
    static func unused(among taken: [String?]) -> ChildColor {
        let used = Set(taken.compactMap { $0?.uppercased() })
        return allCases.first { !used.contains($0.rawValue) } ?? allCases[used.count % allCases.count]
    }

    /// Fallback for a record saved before colours were assigned, so those
    /// children are still told apart instead of all turning blue.
    ///
    /// Derived from the raw bytes, **not** from `hashValue`: Swift seeds its
    /// hasher per process, so a hash-based colour would change on every launch
    /// and differ between the iPhones sharing a plan.
    static func derived(from id: UUID) -> ChildColor {
        allCases[index(derivedFrom: id)]
    }

    /// Split out so it can be tested without touching SwiftUI.
    static func index(derivedFrom id: UUID) -> Int {
        let sum = withUnsafeBytes(of: id.uuid) { bytes in
            bytes.reduce(0) { $0 &+ Int($1) }
        }
        return sum % allCases.count
    }
}

extension Color {
    /// Parses `RRGGBB` / `#RRGGBB`. Returns nil for anything else so callers can
    /// fall back rather than silently rendering black.
    init?(hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value & 0xFF0000) >> 16) / 255.0,
            green: Double((value & 0x00FF00) >> 8) / 255.0,
            blue: Double(value & 0x0000FF) / 255.0,
            opacity: 1.0
        )
    }
}
