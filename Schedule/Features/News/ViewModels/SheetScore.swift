//
//  SheetStore.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import Foundation

@MainActor
final class SheetStore: ObservableObject {
    @Published var a1Text: String = ""
    @Published var firstRow: [String] = []
    @Published var lastUpdatedString: String = "—"
    
    private let spreadsheetID = "1-Tz6jAzcu-dPW3a0J5H7dqSc-8ZzgVDVNH9ABAUvmu0"
    private let gid = "0"
    
    private var pollTask: Task<Void, Never>?
    private let refreshSeconds: UInt64 = 30
    
    func startPolling() async {
        stopPolling()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.fetchFirstRowFromCSV()
                try? await Task.sleep(nanoseconds: refreshSeconds * 1_000_000_000)
            }
        }
    }
    
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
    
    private func csvURL() -> URL {
        URL(string: "https://docs.google.com/spreadsheets/d/\(spreadsheetID)/export?format=csv&gid=\(gid)")!
    }
    
    private func updateTimestamp() {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        lastUpdatedString = f.string(from: Date())
    }
    
    private func fetchFirstRowFromCSV() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: csvURL())
            guard let csv = String(data: data, encoding: .utf8) else { return }
            parseFirstRow(csv)
            updateTimestamp()
        } catch {
            // Handle error silently
        }
    }
    
    private func parseFirstRecord(_ csv: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuotes = false
        var i = csv.startIndex

        while i < csv.endIndex {
            let ch = csv[i]

            if ch == "\"" {
                let next = csv.index(after: i)
                if inQuotes && next < csv.endIndex && csv[next] == "\"" {
                    cur.append("\"")
                    i = next
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                out.append(cur)
                cur.removeAll(keepingCapacity: true)
            } else if (ch == "\n" || ch == "\r") && !inQuotes {
                break
            } else {
                cur.append(ch)
            }

            i = csv.index(after: i)
        }
        out.append(cur)

        return out.map {
            var s = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 {
                s.removeFirst(); s.removeLast()
            }
            return s.replacingOccurrences(of: "\"\"", with: "\"")
        }
    }

    private func parseFirstRow(_ csvString: String) {
        let cells = parseFirstRecord(csvString)
        DispatchQueue.main.async {
            self.a1Text = cells.first ?? ""
            self.firstRow = cells
        }
    }
}
