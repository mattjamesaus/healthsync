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

    /// Appends rows to a monthly CSV, creating the file with a header if needed.
    /// Skips UUIDs already present in the file.
    @discardableResult
    static func appendSamples(
        _ rows: [SampleRow],
        to directory: URL,
        monthKey: String
    ) throws -> Int {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fileURL = directory.appendingPathComponent("\(monthKey).csv")
        let existing = try existingUUIDs(in: fileURL, uuidColumnIndex: 6)
        let newRows = rows.filter { !existing.contains($0.uuid) }
        guard !newRows.isEmpty else { return 0 }

        let lines = newRows.map(sampleLine)
        try append(lines: lines, header: sampleHeader, to: fileURL)
        return newRows.count
    }

    @discardableResult
    static func appendWorkouts(
        _ rows: [WorkoutRow],
        to directory: URL,
        monthKey: String
    ) throws -> Int {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fileURL = directory.appendingPathComponent("\(monthKey).csv")
        let existing = try existingUUIDs(in: fileURL, uuidColumnIndex: 7)
        let newRows = rows.filter { !existing.contains($0.uuid) }
        guard !newRows.isEmpty else { return 0 }

        let lines = newRows.map(workoutLine)
        try append(lines: lines, header: workoutHeader, to: fileURL)
        return newRows.count
    }

    private static func append(lines: [String], header: String, to fileURL: URL) throws {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let content = ([header] + lines).joined(separator: "\n") + "\n"
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        let payload = lines.joined(separator: "\n") + "\n"
        if let data = payload.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    private static func existingUUIDs(in fileURL: URL, uuidColumnIndex: Int) throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        var uuids = Set<String>()
        for (index, line) in content.split(whereSeparator: \.isNewline).enumerated() {
            if index == 0 { continue }
            let columns = parseCSVLine(String(line))
            guard columns.count > uuidColumnIndex else { continue }
            uuids.insert(columns[uuidColumnIndex])
        }
        return uuids
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
