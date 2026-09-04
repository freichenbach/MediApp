import Foundation

/// What kind of number an event carries, if any.
///
/// The categories differ in shape, not just in wording: a temperature is one
/// number, a blood pressure is two, and a blood sugar is one number that means
/// different things depending on which side of the Channel — or the Atlantic —
/// the reading came from. Keeping that in one place stops the editor, the list
/// and the doctor's report from each deciding it separately.
enum MeasurementShape: Equatable {
    /// One number with a unit the person can type themselves.
    case single(defaultUnit: String?)
    /// One number in a unit that is never anything else, so it is printed
    /// beside the field rather than offered for editing. A percentage cannot
    /// be entered in some other unit, and a field inviting one is only a place
    /// for a typo.
    case fixedUnit(String)
    /// Systolic over diastolic.
    case bloodPressure
    /// One number in a unit that has to be chosen from a fixed pair, because
    /// the two differ by a factor of eighteen.
    case bloodSugar
    /// A seizure: which kind it was, and how long it lasted.
    case seizure
    /// Named `noValue` rather than `none` so a switch never has to be read
    /// twice to tell it apart from `Optional.none`.
    case noValue
}

// MARK: - Oxygen saturation

/// SpO₂, in percent.
///
/// One number, one unit, and the only bound worth enforcing: above 100 is not
/// a reading but a slip of the finger. A low value is not a mistake to be
/// argued with — it is the whole reason somebody is writing it down.
enum OxygenSaturation {
    static let unit = "%"

    /// Physically impossible, so it is safe to call it out.
    static func isImpossible(percent: Double) -> Bool {
        percent > 100
    }

    /// Whole numbers: pulse oximeters read them that way, and a decimal would
    /// suggest a precision the device does not have.
    static func description(percent: Double) -> String {
        "\(Int(percent.rounded())) \(unit)"
    }
}

// MARK: - Seizures

/// The kinds of seizure, following the ILAE 2017 classification.
///
/// The wording is the classification's, not a simplification of it. A seizure
/// diary is read by a neurologist, and "atypical absence" means something
/// precise to them that "staring spell" does not — a report that renamed things
/// to sound friendlier would be worth less in the only room where it matters.
///
/// Stored as strings rather than numbers. Codes travel through iCloud and sit
/// in the database for years; a string still says what it means when somebody
/// opens the CloudKit console in two years, and inserting a kind in the middle
/// of the list can never silently renumber the ones already recorded.
enum SeizureType: String, CaseIterable, Identifiable {

    // Generalised onset
    case typicalAbsence = "typical-absence"
    case atypicalAbsence = "atypical-absence"
    case myoclonicAbsence = "myoclonic-absence"
    case tonicClonic = "tonic-clonic"
    case tonic
    case clonic
    case myoclonic
    case atonic
    case epilepticSpasms = "epileptic-spasms"

    // Focal onset
    case focalAware = "focal-aware"
    case focalImpairedAwareness = "focal-impaired-awareness"
    case focalToBilateralTonicClonic = "focal-to-bilateral-tonic-clonic"

    case unknown

    var id: String { rawValue }

    /// One label, already localized, as a plain `String`.
    ///
    /// Not a `LocalizedStringKey`: that lives in SwiftUI, and this type is read
    /// by the report's PDF renderer as well as by the editor. A second
    /// "plain" property beside it would be the same names twice, and the two
    /// would eventually disagree.
    var label: String {
        switch self {
        case .typicalAbsence: return String(localized: "Typical absence")
        case .atypicalAbsence: return String(localized: "Atypical absence")
        case .myoclonicAbsence: return String(localized: "Myoclonic absence")
        case .tonicClonic: return String(localized: "Tonic-clonic")
        case .tonic: return String(localized: "Tonic")
        case .clonic: return String(localized: "Clonic")
        case .myoclonic: return String(localized: "Myoclonic")
        case .atonic: return String(localized: "Atonic (drop attack)")
        case .epilepticSpasms: return String(localized: "Epileptic spasms")
        case .focalAware: return String(localized: "Focal, aware")
        case .focalImpairedAwareness: return String(localized: "Focal, impaired awareness")
        case .focalToBilateralTonicClonic: return String(localized: "Focal to bilateral tonic-clonic")
        case .unknown: return String(localized: "Other or unclear")
        }
    }

    /// How the picker is grouped, because thirteen flat entries are hard to
    /// scan while something is happening in the room.
    enum Group: String, CaseIterable, Identifiable {
        case generalised, focal, other
        var id: String { rawValue }

        var label: String {
            switch self {
            case .generalised: return String(localized: "Generalised onset")
            case .focal: return String(localized: "Focal onset")
            case .other: return String(localized: "Unknown onset")
            }
        }

        var types: [SeizureType] {
            switch self {
            case .generalised:
                return [.typicalAbsence, .atypicalAbsence, .myoclonicAbsence,
                        .tonicClonic, .tonic, .clonic, .myoclonic, .atonic, .epilepticSpasms]
            case .focal:
                return [.focalAware, .focalImpairedAwareness, .focalToBilateralTonicClonic]
            case .other:
                return [.unknown]
            }
        }
    }

    static func from(code: String?) -> SeizureType? {
        guard let code else { return nil }
        return SeizureType(rawValue: code.trimmingCharacters(in: .whitespaces))
    }
}

/// How long a seizure lasted, kept in seconds.
///
/// Seconds because that is what absences are counted in — five, twelve, twenty
/// — and a field asking for minutes would force a decimal onto the most common
/// entry of all.
enum SeizureDuration {
    static let unit = "s"

    /// "18 s" below a minute, "2:15 min" above it. Nobody says "135 seconds".
    static func description(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        guard total >= 60 else { return "\(total) \(unit)" }
        let minutes = total / 60
        let rest = total % 60
        return String(format: "%d:%02d min", minutes, rest)
    }

    // There is deliberately no threshold here, and none is to be added.
    //
    // Five minutes is the figure most epilepsy emergency plans are written
    // around, and an earlier version said so beside the duration field. It is
    // gone on purpose: the app records what happened and does not read it.
    // A line that lights up at a particular number is the app judging a
    // measurement, which is the step that turns a diary into a medical device
    // — and it would be doing it without knowing this child, this diagnosis or
    // this emergency plan. The plan the family was given says what their
    // number is; the app has no business having an opinion next to it.
}

// MARK: - Blood pressure

/// Systolic over diastolic, in mmHg.
///
/// No other unit is offered. mmHg is what every cuff in Europe reads and what
/// every guideline is written in; kPa exists but offering it would invite a
/// reading in the wrong one, and a blood pressure in the wrong unit is not an
/// inconvenience but a wrong number in a medical record.
enum BloodPressure {
    static let unit = "mmHg"

    /// "120/80", the way it is spoken and written everywhere.
    static func description(systolic: Double, diastolic: Double) -> String {
        "\(whole(systolic))/\(whole(diastolic))"
    }

    /// Blood pressure is always whole numbers. A cuff that reads 120.4 does not
    /// exist, and the decimal would only be noise on the page.
    private static func whole(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    /// What a plausible reading looks like, used to warn rather than to refuse.
    ///
    /// Deliberately wide, and deliberately only a warning: children's pressures
    /// sit far below adults', and a low reading in a small child is exactly the
    /// sort of thing that must reach the doctor rather than be rejected by a
    /// text field.
    static let plausibleSystolic = 40.0...260.0
    static let plausibleDiastolic = 20.0...160.0

    /// The one relationship that is never a real reading, only a typo or two
    /// numbers entered the wrong way round.
    static func isReversed(systolic: Double, diastolic: Double) -> Bool {
        systolic > 0 && diastolic > 0 && diastolic >= systolic
    }
}

// MARK: - Blood sugar

/// mg/dL and mmol/L, and the conversion between them.
///
/// Both are in daily use — mg/dL in Germany, the US and Spain, mmol/L in the
/// UK and much of northern Europe — and they differ by a factor of eighteen. A
/// household where one person reads one and another reads the other is exactly
/// the household this app is for, so the value is stored as entered, in the
/// unit it was entered in, and the other one is shown alongside.
///
/// Storing a converted number instead would be the tempting shortcut and the
/// wrong one: it would round somebody's reading and hand the doctor a figure
/// nobody ever saw on a meter.
enum BloodSugarUnit: String, CaseIterable, Identifiable {
    case mgPerDeciliter = "mg/dl"
    case mmolPerLiter = "mmol/l"

    var id: String { rawValue }

    var label: String { rawValue }

    /// Molar mass of glucose over ten. The rounded 18 is common in print and
    /// off by a tenth of a percent; at 18.0182 the round trip through both
    /// units comes back to where it started.
    private static let factor = 18.0182

    var other: BloodSugarUnit {
        self == .mgPerDeciliter ? .mmolPerLiter : .mgPerDeciliter
    }

    /// Converts `value` from this unit into `target`.
    func convert(_ value: Double, to target: BloodSugarUnit) -> Double {
        guard self != target else { return value }
        switch target {
        case .mmolPerLiter: return value / Self.factor
        case .mgPerDeciliter: return value * Self.factor
        }
    }

    /// How many decimals the unit is read to. mg/dL comes off a meter whole;
    /// mmol/L is spoken to one decimal.
    var fractionDigits: Int {
        self == .mgPerDeciliter ? 0 : 1
    }

    func format(_ value: Double) -> String {
        let rounded = value.formatted(
            .number.precision(.fractionLength(0...fractionDigits)).grouping(.never)
        )
        return "\(rounded) \(rawValue)"
    }

    /// "110 mg/dl (6.1 mmol/l)" — the entered figure first, the conversion in
    /// brackets, so nobody has to wonder which one was actually read.
    func descriptionWithConversion(_ value: Double) -> String {
        let converted = convert(value, to: other)
        return "\(format(value)) (\(other.format(converted)))"
    }

    static func from(unitString: String?) -> BloodSugarUnit? {
        guard let unitString else { return nil }
        let cleaned = unitString.trimmingCharacters(in: .whitespaces).lowercased()
        return allCases.first { $0.rawValue == cleaned }
    }

    /// Wide on purpose, and only ever a warning. A reading of 30 mg/dL is a
    /// medical emergency, not a typo to be rejected.
    var plausibleRange: ClosedRange<Double> {
        self == .mgPerDeciliter ? 20...800 : 1.1...44.4
    }
}
