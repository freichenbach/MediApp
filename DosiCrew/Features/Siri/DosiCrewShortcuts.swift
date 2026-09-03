import AppIntents

/// The sentences Siri listens for, and the entries that show up in Shortcuts
/// without anybody having to build them by hand.
///
/// Phrases have to contain `\(.applicationName)` — Siri needs the app named to
/// know which of many "record a dose" it is meant to run. Several wordings per
/// intent on purpose: nobody remembers a single prescribed sentence, and the
/// cost of listing the obvious variants is one line each.
struct DosiCrewShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextDoseIntent(),
            phrases: [
                "What is next in \(.applicationName)?",
                "When is the next dose in \(.applicationName)?",
                "Ask \(.applicationName) what is due"
            ],
            shortTitle: "Next dose",
            systemImageName: "clock.badge.questionmark"
        )

        AppShortcut(
            intent: LogDoseIntent(),
            phrases: [
                "Record a dose in \(.applicationName)",
                "Tick off a dose in \(.applicationName)",
                "\(.applicationName) given"
            ],
            shortTitle: "Record a dose",
            systemImageName: "checkmark.circle"
        )
    }
}
