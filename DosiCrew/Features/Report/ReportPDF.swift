import Foundation
import UIKit

/// Lays the report out as a PDF, because that is what gets handed across a
/// desk, printed, or attached to an email to the practice.
///
/// Written against `UIGraphicsPDFRenderer` rather than rendering a SwiftUI view
/// to an image: a report runs to several pages, and page breaks have to fall
/// between rows rather than through them.
enum ReportPDF {

    // A4. The practice will print this, and printing A4 content on A4 paper is
    // the one thing that never surprises anybody.
    private static let pageSize = CGSize(width: 595.2, height: 841.8)
    private static let margin: CGFloat = 48
    private static let bottomMargin: CGFloat = 56

    static func data(for report: DoseReport.Report) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            let canvas = Canvas(context: context, pageSize: pageSize, margin: margin, bottomMargin: bottomMargin)
            canvas.beginPage()

            header(report, on: canvas)
            caveat(on: canvas)
            summary(report, on: canvas)
            perMedication(report, on: canvas)
            history(report, on: canvas)
            events(report, on: canvas)

            canvas.finishPageNumbers()
        }
    }

    /// A filename somebody can find again in a mailbox six weeks later.
    static func filename(for report: DoseReport.Report) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = report.patientName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = name.isEmpty ? "DosiCrew" : "DosiCrew \(name)"
        return "\(stem) \(formatter.string(from: report.from))–\(formatter.string(from: report.to)).pdf"
    }

    /// Writes it where a share sheet can pick it up. Replaces any earlier file
    /// of the same name so a second export does not hand over a stale one.
    static func write(_ report: DoseReport.Report) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename(for: report))
        try? FileManager.default.removeItem(at: url)
        try data(for: report).write(to: url, options: .atomic)
        return url
    }

    // MARK: - Sections

    private static func header(_ report: DoseReport.Report, on canvas: Canvas) {
        canvas.text(String(localized: "Medication record"), style: .title)
        canvas.gap(2)

        var line = report.patientName.isEmpty
            ? String(localized: "Child")
            : report.patientName
        if let birthDate = report.patientBirthDate {
            line += " · " + String(
                localized: "born \(birthDate.formatted(date: .numeric, time: .omitted))"
            )
        }
        if report.patientWeightKg > 0 {
            let weight = report.patientWeightKg.formatted(.number.precision(.fractionLength(0...1)))
            line += " · " + String(localized: "\(weight) kg")
        }
        canvas.text(line, style: .subtitle)

        canvas.text(
            String(
                localized: "\(report.from.formatted(date: .abbreviated, time: .omitted)) to \(report.to.formatted(date: .abbreviated, time: .omitted))"
            ),
            style: .subtitle
        )
        canvas.text(
            String(localized: "Created \(report.generatedAt.formatted(date: .abbreviated, time: .shortened)) with DosiCrew"),
            style: .caption
        )
        canvas.gap(10)
        canvas.rule()
        canvas.gap(10)
    }

    /// The most important paragraph on the page.
    ///
    /// Everything below is a record of what people typed into a phone, not an
    /// observation of what happened. A blank is somebody who had their hands
    /// full, not necessarily a dose that was missed — and a doctor could change
    /// a prescription over that difference.
    private static func caveat(on canvas: Canvas) {
        canvas.box(
            String(localized: "This lists what was recorded in the app, not what was observed. A dose shown as “not recorded” may well have been given without anybody reaching for their phone. Times come from the phone of whoever ticked the dose off. DosiCrew does not check doses, interactions or contraindications.")
        )
        canvas.gap(14)
    }

    private static func summary(_ report: DoseReport.Report, on canvas: Canvas) {
        canvas.text(String(localized: "At a glance"), style: .heading)
        canvas.gap(4)

        let counts: [(String, Int)] = [
            (String(localized: "Doses due"), report.planned),
            (String(localized: "Given on time"), report.given),
            (String(localized: "Given late"), report.late),
            (String(localized: "Deliberately skipped"), report.skipped),
            (String(localized: "Refused by the child"), report.refused),
            (String(localized: "Not recorded"), report.notRecorded),
            (String(localized: "Extra doses"), report.extras),
            (String(localized: "Given twice by two people"), report.duplicates)
        ]
        for (label, value) in counts where value > 0 || label == counts[0].0 {
            canvas.row([
                Cell(text: label, width: 260),
                Cell(text: "\(value)", width: 60, alignment: .right)
            ])
        }
        canvas.gap(4)
        canvas.text(
            String(localized: "“Given late” means more than an hour after the planned time."),
            style: .caption
        )
        canvas.gap(14)
    }

    private static func perMedication(_ report: DoseReport.Report, on canvas: Canvas) {
        guard !report.tallies.isEmpty else { return }
        canvas.text(String(localized: "Per medication"), style: .heading)
        canvas.gap(4)

        canvas.row([
            Cell(text: String(localized: "Medication"), width: 140, style: .tableHeader),
            Cell(text: String(localized: "Dose"), width: 70, style: .tableHeader),
            Cell(text: String(localized: "Due"), width: 44, alignment: .right, style: .tableHeader),
            Cell(text: String(localized: "Given"), width: 50, alignment: .right, style: .tableHeader),
            Cell(text: String(localized: "Late"), width: 40, alignment: .right, style: .tableHeader),
            Cell(text: String(localized: "Missing"), width: 60, alignment: .right, style: .tableHeader),
            Cell(text: String(localized: "Extra"), width: 45, alignment: .right, style: .tableHeader),
            Cell(text: String(localized: "Twice"), width: 42, alignment: .right, style: .tableHeader)
        ])
        canvas.rule()

        for tally in report.tallies {
            canvas.row([
                Cell(text: tally.name, width: 140),
                Cell(text: tally.doseDescription, width: 70),
                Cell(text: "\(tally.planned)", width: 44, alignment: .right),
                Cell(text: "\(tally.given)", width: 50, alignment: .right),
                Cell(text: "\(tally.late)", width: 40, alignment: .right),
                Cell(text: "\(tally.notRecorded + tally.skipped + tally.refused)", width: 60, alignment: .right),
                Cell(text: "\(tally.extras)", width: 45, alignment: .right),
                Cell(text: "\(tally.duplicates)", width: 42, alignment: .right)
            ])
            if let instructions = tally.instructions, !instructions.isEmpty {
                canvas.text(instructions, style: .caption, indent: 12)
            }
        }
        canvas.gap(4)
        canvas.text(
            String(localized: "“Missing” gathers deliberately skipped, refused and not recorded; the columns above separate them."),
            style: .caption
        )
        canvas.gap(14)
    }

    private static func history(_ report: DoseReport.Report, on canvas: Canvas) {
        let days = report.days.filter { !$0.isEmpty }
        guard !days.isEmpty else { return }

        canvas.text(String(localized: "Day by day"), style: .heading)
        canvas.gap(4)

        for day in days {
            // Keeps a date from being the last line on a page with its doses
            // overleaf.
            canvas.keepTogether(height: 42)
            canvas.text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide)), style: .dayHeading)

            for entry in day.entries {
                canvas.row([
                    Cell(text: TimeText.of(entry.scheduledAt), width: 52, style: .mono),
                    Cell(text: entry.medicationName, width: 150),
                    Cell(text: entry.doseDescription, width: 62),
                    Cell(text: outcomeLabel(entry.outcome), width: 108),
                    Cell(text: actualTime(for: entry), width: 60, style: .mono),
                    Cell(text: entry.personName ?? "", width: 80, style: .caption)
                ])
                // The line a doctor needs to see, spelled out rather than
                // left as a number in a column: this dose went in twice.
                for duplicate in entry.duplicates {
                    let when = duplicate.takenAt.map(TimeText.of) ?? ""
                    let who = duplicate.personName ?? String(localized: "somebody else")
                    canvas.text(
                        String(localized: "Also given by \(who) at \(when) — the child had this dose twice."),
                        style: .caption,
                        indent: 52
                    )
                }
                if let note = entry.note, !note.isEmpty {
                    canvas.text(note, style: .caption, indent: 52)
                }
            }

            for extra in day.extras {
                canvas.row([
                    Cell(text: TimeText.of(extra.takenAt), width: 52, style: .mono),
                    Cell(text: extra.medicationName, width: 150),
                    Cell(text: extra.doseDescription, width: 62),
                    Cell(text: String(localized: "Extra dose"), width: 108),
                    Cell(text: "", width: 60),
                    Cell(text: extra.personName ?? "", width: 80, style: .caption)
                ])
                if let note = extra.note, !note.isEmpty {
                    canvas.text(note, style: .caption, indent: 52)
                }
            }
            canvas.gap(8)
        }
        canvas.gap(6)
    }

    private static func events(_ report: DoseReport.Report, on canvas: Canvas) {
        guard !report.events.isEmpty else { return }
        canvas.keepTogether(height: 60)
        canvas.text(String(localized: "Events"), style: .heading)
        canvas.gap(4)

        for event in report.events {
            canvas.row([
                Cell(text: event.timestamp.formatted(date: .numeric, time: .shortened), width: 108, style: .mono),
                Cell(text: event.title, width: 180),
                Cell(text: event.measurement ?? "", width: 90),
                Cell(text: event.personName ?? "", width: 84, style: .caption)
            ])
            if let note = event.note, !note.isEmpty {
                canvas.text(note, style: .caption, indent: 108)
            }
        }
    }

    // MARK: - Wording

    private static func outcomeLabel(_ outcome: DoseReport.Outcome) -> String {
        switch outcome {
        case .given: return String(localized: "Given")
        case .late: return String(localized: "Given late")
        case .skipped: return String(localized: "Skipped")
        case .refused: return String(localized: "Refused")
        case .notRecorded: return String(localized: "Not recorded")
        }
    }

    private static func actualTime(for entry: DoseReport.Entry) -> String {
        guard let takenAt = entry.takenAt else { return "" }
        guard let deviation = entry.deviationMinutes, deviation != 0 else {
            return TimeText.of(takenAt)
        }
        let sign = deviation > 0 ? "+" : "−"
        return "\(TimeText.of(takenAt)) (\(sign)\(abs(deviation))′)"
    }

    // MARK: - Drawing

    private struct Cell {
        var text: String
        var width: CGFloat
        var alignment: NSTextAlignment = .left
        var style: Style = .body
    }

    private enum Style {
        case title, subtitle, heading, dayHeading, body, caption, tableHeader, mono

        var font: UIFont {
            switch self {
            case .title: return .systemFont(ofSize: 22, weight: .semibold)
            case .subtitle: return .systemFont(ofSize: 11)
            case .heading: return .systemFont(ofSize: 13, weight: .semibold)
            case .dayHeading: return .systemFont(ofSize: 11, weight: .semibold)
            case .body: return .systemFont(ofSize: 10)
            case .caption: return .systemFont(ofSize: 8.5)
            case .tableHeader: return .systemFont(ofSize: 9, weight: .semibold)
            case .mono: return .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            }
        }

        var colour: UIColor {
            switch self {
            case .caption, .subtitle, .tableHeader: return UIColor(white: 0.35, alpha: 1)
            default: return .black
            }
        }
    }

    /// Keeps track of where the pen is and starts a new page before anything
    /// would fall off the bottom.
    private final class Canvas {
        private let context: UIGraphicsPDFRendererContext
        private let pageSize: CGSize
        private let margin: CGFloat
        private let bottomMargin: CGFloat
        private var y: CGFloat = 0
        private var pageCount = 0

        init(context: UIGraphicsPDFRendererContext, pageSize: CGSize, margin: CGFloat, bottomMargin: CGFloat) {
            self.context = context
            self.pageSize = pageSize
            self.margin = margin
            self.bottomMargin = bottomMargin
        }

        var contentWidth: CGFloat { pageSize.width - margin * 2 }

        func beginPage() {
            context.beginPage()
            pageCount += 1
            y = margin
            drawPageNumber()
        }

        private func room(for height: CGFloat) -> Bool {
            y + height <= pageSize.height - bottomMargin
        }

        /// Starts a new page unless `height` still fits — used before a heading
        /// so it does not end up orphaned at the foot of a page.
        func keepTogether(height: CGFloat) {
            if !room(for: height) { beginPage() }
        }

        func gap(_ height: CGFloat) {
            y += height
        }

        func rule() {
            if !room(for: 8) { beginPage() }
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: y))
            path.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
            UIColor(white: 0.8, alpha: 1).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            y += 6
        }

        func text(_ string: String, style: Style, indent: CGFloat = 0) {
            guard !string.isEmpty else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: style.font,
                .foregroundColor: style.colour
            ]
            let width = contentWidth - indent
            let bounding = (string as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
            let height = ceil(bounding.height) + 2
            if !room(for: height) { beginPage() }
            (string as NSString).draw(
                with: CGRect(x: margin + indent, y: y, width: width, height: height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
            y += height
        }

        /// One line of cells. Long text is clipped rather than wrapped: a table
        /// whose rows are different heights is harder to read across, and the
        /// full text of a note goes on its own line underneath anyway.
        func row(_ cells: [Cell]) {
            let height: CGFloat = 14
            if !room(for: height) { beginPage() }
            var x = margin
            for cell in cells {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = cell.alignment
                paragraph.lineBreakMode = .byTruncatingTail
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: cell.style.font,
                    .foregroundColor: cell.style.colour,
                    .paragraphStyle: paragraph
                ]
                (cell.text as NSString).draw(
                    with: CGRect(x: x, y: y + 1, width: cell.width - 4, height: height),
                    options: [.usesLineFragmentOrigin],
                    attributes: attributes,
                    context: nil
                )
                x += cell.width
            }
            y += height
        }

        /// The caveat, set apart so it is not read as one more sentence.
        func box(_ string: String) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor(white: 0.2, alpha: 1)
            ]
            let inset: CGFloat = 8
            let width = contentWidth - inset * 2
            let bounding = (string as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
            let height = ceil(bounding.height) + inset * 2
            if !room(for: height) { beginPage() }

            let frame = CGRect(x: margin, y: y, width: contentWidth, height: height)
            let path = UIBezierPath(roundedRect: frame, cornerRadius: 4)
            UIColor(white: 0.94, alpha: 1).setFill()
            path.fill()

            (string as NSString).draw(
                with: CGRect(x: margin + inset, y: y + inset, width: width, height: height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
            y += height
        }

        private func drawPageNumber() {
            let text = String(localized: "Page \(pageCount)")
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor(white: 0.5, alpha: 1)
            ]
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            var withAlignment = attributes
            withAlignment[.paragraphStyle] = paragraph
            (text as NSString).draw(
                with: CGRect(
                    x: margin,
                    y: pageSize.height - bottomMargin + 16,
                    width: contentWidth,
                    height: 12
                ),
                options: [.usesLineFragmentOrigin],
                attributes: withAlignment,
                context: nil
            )
        }

        /// Nothing to do once page numbers are drawn as pages begin; kept as
        /// the single place to change if they ever need "3 of 7".
        func finishPageNumbers() {}
    }
}
