import Foundation

enum CSVWriter {
    static let sampleHeader =
        "datetime,end_datetime,type,unit,value,source,uuid"
    static let workoutHeader =
        "datetime,end_datetime,workout_type,duration_seconds,total_energy_kcal,total_distance_m,source,uuid"

    static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n")
            || field.contains("\r")
        {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter.export.string(from: date)
    }

    static func sampleLine(_ row: SampleRow) -> String {
        [
            iso8601(row.start),
            iso8601(row.end),
            row.type,
            row.unit,
            row.value,
            row.source,
            row.uuid,
        ]
        .map(escape)
        .joined(separator: ",")
    }

    static func workoutLine(_ row: WorkoutRow) -> String {
        [
            iso8601(row.start),
            iso8601(row.end),
            row.workoutType,
            formatOptional(row.durationSeconds),
            optionalNumber(row.totalEnergyKilocalories),
            optionalNumber(row.totalDistanceMeters),
            row.source,
            row.uuid,
        ]
        .map(escape)
        .joined(separator: ",")
    }

    /// Merges rows into a monthly CSV. Skips UUIDs already present.
    /// UUID column indexes stay 6 for samples and 7 for workouts.
    static func mergeSamples(_ rows: [SampleRow], existing: Data?) -> (data: Data, added: Int) {
        merge(
            lines: rows.map { ($0.uuid, sampleLine($0)) },
            existing: existing,
            header: sampleHeader,
            uuidColumnIndex: 6
        )
    }

    static func mergeWorkouts(_ rows: [WorkoutRow], existing: Data?) -> (data: Data, added: Int) {
        merge(
            lines: rows.map { ($0.uuid, workoutLine($0)) },
            existing: existing,
            header: workoutHeader,
            uuidColumnIndex: 7
        )
    }

    private static func merge(
        lines: [(uuid: String, line: String)],
        existing: Data?,
        header: String,
        uuidColumnIndex: Int
    ) -> (data: Data, added: Int) {
        let existingText = existing.flatMap { String(data: $0, encoding: .utf8) }
        let known = uuids(in: existingText, uuidColumnIndex: uuidColumnIndex)
        let newLines = lines.compactMap { known.contains($0.uuid) ? nil : $0.line }
        guard !newLines.isEmpty else {
            return (existing ?? Data(), 0)
        }

        let content: String
        if let existingText, !existingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var base = existingText
            if !base.hasSuffix("\n") {
                base.append("\n")
            }
            content = base + newLines.joined(separator: "\n") + "\n"
        } else {
            content = ([header] + newLines).joined(separator: "\n") + "\n"
        }
        return (Data(content.utf8), newLines.count)
    }

    private static func uuids(in content: String?, uuidColumnIndex: Int) -> Set<String> {
        guard let content else { return [] }
        var values = Set<String>()
        for (index, line) in content.split(whereSeparator: \.isNewline).enumerated() {
            if index == 0 { continue }
            let columns = parseCSVLine(String(line))
            guard columns.count > uuidColumnIndex else { continue }
            values.insert(columns[uuidColumnIndex])
        }
        return values
    }

    /// Minimal CSV line parser for uuid extraction (handles quoted fields).
    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\"" {
                let next = line.index(after: i)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    i = line.index(after: next)
                    continue
                }
                inQuotes.toggle()
                i = next
                continue
            }
            if ch == ",", !inQuotes {
                fields.append(current)
                current = ""
                i = line.index(after: i)
                continue
            }
            current.append(ch)
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }

    private static func optionalNumber(_ value: Double?) -> String {
        guard let value else { return "" }
        return formatOptional(value)
    }

    private static func formatOptional(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.6g", value)
    }
}

extension ISO8601DateFormatter {
    static let export: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

enum MonthKey {
    static func from(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}
