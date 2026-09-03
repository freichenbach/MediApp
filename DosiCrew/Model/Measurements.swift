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
    /// Systolic over diastolic.
    case bloodPressure
    /// One number in a unit that has to be chosen from a fixed pair, because
    /// the two differ by a factor of eighteen.
    case bloodSugar
    /// Named `noValue` rather than `none` so a switch never has to be read
    /// twice to tell it apart from `Optional.none`.
    case noValue
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
