import SwiftUI

/// Reading and writing a typed amount — a dose, a temperature.
///
/// Exists because `TextField(value:format:)` bound to a `Double` cannot show an
/// empty field: a fresh medication renders "0", the placeholder never appears,
/// and the cursor lands to the left of that zero, so entering "5" produces "50"
/// unless the person first navigates past it. Going through text instead means
/// nothing means nothing.
enum DecimalText {

    /// What to put in the field for a stored amount — nothing at all when there
    /// is none.
    static func text(for amount: Double) -> String {
        guard amount > 0 else { return "" }
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }

    /// Reads a typed amount, accepting either decimal separator.
    ///
    /// Deliberately *not* `NumberFormatter.number(from:)`: in an English locale
    /// that reads "5,5" as a grouping separator and returns 55. On a decimal pad
    /// the separator shown depends on the keyboard, and for a medication dose a
    /// silent factor of ten is not an acceptable failure mode. So every comma
    /// and dot means the same thing here, and two of them mean the input is not
    /// a number.
    static func value(of text: String) -> Double {
        let cleaned = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, cleaned.filter({ $0 == "." }).count <= 1 else { return 0 }
        return max(0, Double(cleaned) ?? 0)
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        // No grouping separator: whatever comes out has to be typeable back in,
        // and `value(of:)` reads every separator as a decimal point.
        formatter.usesGroupingSeparator = false
        return formatter
    }()
}

extension View {

    /// Gives every keyboard on this screen a way out.
    ///
    /// Two things go wrong without it, and the second one traps the screen
    /// rather than merely annoying: a decimal pad has no return key at all, and
    /// inside the tab bar the keyboard covers the tabs — so there is nothing
    /// left to tap that would put it away, and the tab cannot be left.
    func dismissibleKeyboard() -> some View {
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { KeyboardDismiss.now() }
                }
            }
    }
}

enum KeyboardDismiss {
    /// Resigns whatever holds first responder.
    ///
    /// Through UIKit rather than a `@FocusState` per screen: it works for every
    /// field without each one having to be wired up, which is what makes it
    /// safe to rely on as the way out.
    static func now() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
