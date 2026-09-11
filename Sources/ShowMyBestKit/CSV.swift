import Foundation

/// RFC 4180 CSV (FMT-1) that keeps every record's original bytes.
///
/// The app is only allowed to change `istvan_rating` cells and to append rows
/// (RAT-5); every other row must come back out of the file byte for byte,
/// quoting and line endings included (RAT-6). So a record carries its raw bytes
/// and the byte ranges its fields occupy: editing a cell splices the new value
/// into those bytes and leaves the rest of the file alone.
///
/// Bytes rather than `Character`s on purpose. Swift reads CRLF as one grapheme
/// cluster, so character-wise scanning cannot tell a CR from a CRLF, and the
/// whole point here is to preserve the difference.

public enum CSVError: Error, CustomStringConvertible {
    case notUTF8
    case unbalancedQuote(line: Int)
    case empty

    public var description: String {
        switch self {
        case .notUTF8: return "the file is not valid UTF-8"
        case .unbalancedQuote(let line): return "line \(line): unbalanced quote"
        case .empty: return "the file is empty"
        }
    }

    /// The line the problem is on, for SYN-3's "naming the file and the line".
    public var line: Int? {
        if case .unbalancedQuote(let line) = self { return line }
        return nil
    }
}

private let comma = UInt8(ascii: ",")
private let quote = UInt8(ascii: "\"")
private let carriageReturn = UInt8(ascii: "\r")
private let newline = UInt8(ascii: "\n")

public struct CSVRecord {
    /// The record exactly as it appears in the file, terminator included.
    public private(set) var bytes: [UInt8]
    /// One byte range per field, covering the field's raw form (surrounding
    /// quotes included, delimiters excluded).
    public private(set) var fieldRanges: [Range<Int>]
    /// Decoded field values, quoting resolved.
    public private(set) var values: [String]
    /// False for a last record the file does not terminate.
    public private(set) var hasTerminator: Bool
    /// 1-based line the record starts on, for error messages.
    public let line: Int

    public var raw: String { String(decoding: bytes, as: UTF8.self) }

    init(bytes: [UInt8], fieldRanges: [Range<Int>], values: [String], hasTerminator: Bool, line: Int) {
        self.bytes = bytes
        self.fieldRanges = fieldRanges
        self.values = values
        self.hasTerminator = hasTerminator
        self.line = line
    }

    public func value(at index: Int) -> String {
        index >= 0 && index < values.count ? values[index] : ""
    }

    /// Splices a new value into one field, leaving every other byte alone.
    public mutating func setValue(_ value: String, at index: Int) {
        guard index >= 0, index < fieldRanges.count else { return }
        var newBytes = bytes
        newBytes.replaceSubrange(fieldRanges[index], with: Array(CSV.escape(value).utf8))
        let reparsed = CSV.parseRecord(newBytes, line: line)
        bytes = reparsed.bytes
        fieldRanges = reparsed.fieldRanges
        values = reparsed.values
        hasTerminator = reparsed.hasTerminator
    }

    /// Gives an unterminated record a line ending, so a row can be appended
    /// after it (RAT-6: using the file's own ending).
    public mutating func appendTerminator(_ lineEnding: String) {
        guard !hasTerminator else { return }
        bytes.append(contentsOf: Array(lineEnding.utf8))
        hasTerminator = true
    }
}

public struct CSVDocument {
    public var headerNames: [String]
    public var headerRecord: CSVRecord
    public var records: [CSVRecord]
    /// The line ending the file already uses; appended rows reuse it (RAT-6).
    public var lineEnding: String
    /// Preserved so a file that arrived with a byte order mark round-trips.
    public var hasBOM: Bool

    public func columnIndex(_ name: String) -> Int? { headerNames.firstIndex(of: name) }
    public func hasColumn(_ name: String) -> Bool { columnIndex(name) != nil }

    /// The whole file as it should be written back.
    public func serialized() -> Data {
        var bytes: [UInt8] = []
        if hasBOM { bytes.append(contentsOf: [0xEF, 0xBB, 0xBF]) }
        bytes.append(contentsOf: headerRecord.bytes)
        for record in records { bytes.append(contentsOf: record.bytes) }
        return Data(bytes)
    }

    /// Builds a record with one field per column from the values given by
    /// column name; every other column is left empty (RAT-3).
    public func makeRecord(_ values: [String: String]) -> CSVRecord {
        let fields = headerNames.map { CSV.escape(values[$0] ?? "") }
        let raw = fields.joined(separator: ",") + lineEnding
        return CSV.parseRecord(Array(raw.utf8), line: 0)
    }
}

public enum CSV {
    public static func escape(_ value: String) -> String {
        let needsQuotes = value.contains { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func parse(data: Data) throws -> CSVDocument {
        var bytes = [UInt8](data)
        var hasBOM = false
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            hasBOM = true
            bytes.removeFirst(3)
        }
        guard !bytes.isEmpty else { throw CSVError.empty }
        guard String(data: Data(bytes), encoding: .utf8) != nil else { throw CSVError.notUTF8 }

        var records: [CSVRecord] = []
        var position = 0
        var line = 1
        while position < bytes.count {
            let record = try scanRecord(bytes, from: &position, line: line)
            // A quoted field can hold line breaks, so a record is not always
            // one line: count what it actually spans.
            var spanned = record.bytes.reduce(0) { $0 + ($1 == newline ? 1 : 0) }
            if record.bytes.last == carriageReturn { spanned += 1 }
            line += spanned
            records.append(record)
        }
        guard let header = records.first else { throw CSVError.empty }

        // CRLF unless the file itself says otherwise (FMT-3).
        var lineEnding = "\r\n"
        if header.hasTerminator {
            lineEnding = header.bytes.suffix(2) == [carriageReturn, newline]
                ? "\r\n"
                : (header.bytes.last == newline ? "\n" : "\r")
        }

        return CSVDocument(
            headerNames: header.values,
            headerRecord: header,
            records: Array(records.dropFirst()),
            lineEnding: lineEnding,
            hasBOM: hasBOM
        )
    }

    /// Re-reads one record's bytes. Used after a field is spliced.
    static func parseRecord(_ bytes: [UInt8], line: Int) -> CSVRecord {
        var position = 0
        if let record = try? scanRecord(bytes, from: &position, line: line) { return record }
        // Only reachable for bytes this file did not produce; keep them whole.
        return CSVRecord(bytes: bytes, fieldRanges: [], values: [], hasTerminator: false, line: line)
    }

    private static func scanRecord(_ bytes: [UInt8], from position: inout Int, line: Int) throws -> CSVRecord {
        let recordStart = position
        var fieldRanges: [Range<Int>] = []
        var values: [String] = []

        while true {
            let fieldStart = position
            var value: [UInt8] = []

            if position < bytes.count, bytes[position] == quote {
                position += 1
                var closed = false
                while position < bytes.count {
                    if bytes[position] == quote {
                        position += 1
                        if position < bytes.count, bytes[position] == quote {
                            value.append(quote)   // an escaped quote
                            position += 1
                        } else {
                            closed = true
                            break
                        }
                    } else {
                        value.append(bytes[position])
                        position += 1
                    }
                }
                guard closed else { throw CSVError.unbalancedQuote(line: line) }
            }
            // Everything up to the next delimiter or terminator: for an
            // unquoted field that is the whole value, and for a quoted one it
            // is trailing junk we keep rather than reject.
            while position < bytes.count,
                  bytes[position] != comma, bytes[position] != carriageReturn, bytes[position] != newline {
                value.append(bytes[position])
                position += 1
            }

            fieldRanges.append((fieldStart - recordStart)..<(position - recordStart))
            values.append(String(decoding: value, as: UTF8.self))

            if position < bytes.count, bytes[position] == comma {
                position += 1
                continue
            }
            break
        }

        var hasTerminator = false
        if position < bytes.count {
            if bytes[position] == carriageReturn {
                position += 1
                if position < bytes.count, bytes[position] == newline { position += 1 }
                hasTerminator = true
            } else if bytes[position] == newline {
                position += 1
                hasTerminator = true
            }
        }

        return CSVRecord(
            bytes: Array(bytes[recordStart..<position]),
            fieldRanges: fieldRanges,
            values: values,
            hasTerminator: hasTerminator,
            line: line
        )
    }
}
