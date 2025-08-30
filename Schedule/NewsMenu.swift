//
//  NewsMenu.swift
//  Schedule
//
//  Created by Andreas Royset on 8/28/25.
//

import Foundation
import SwiftUI

struct NewsMenu: View {
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    @StateObject var store = SheetStore()
    
    var body: some View {
        VStack {
            Text("Saint Francis News")
                .font(.system(
                    size: iPad ? 34 : 22,
                    weight: .bold,
                    design: .monospaced
                ))
                .padding(12)
                .foregroundStyle(PrimaryColor.opacity(1))
            
            Divider()
            
            ScrollView {
                // A1 value (plain text)
                Text(store.a1Text.isEmpty ? "—" : store.a1Text)
                    .font(.system(size: iPad ? 20 : 12, weight: .semibold))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SecondaryColor)
                    .foregroundStyle(PrimaryColor)
                    .cornerRadius(8)

                
            }
            
            Divider()
            
            Text("Email acroyset@gmail.com if you want to put your announcement on here. \n\nLast updated: \(store.lastUpdatedString)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            .padding()
        }
        .task { await store.startPolling() }   // begin 10s polling
        .onDisappear { store.stopPolling() }   // stop when view goes away
    }
}

@MainActor
final class SheetStore: ObservableObject {
    @Published var a1Text: String = ""
    @Published var firstRow: [String] = []
    @Published var lastUpdatedString: String = "—"
    
    // === Configure these two ===
    private let spreadsheetID = "1-Tz6jAzcu-dPW3a0J5H7dqSc-8ZzgVDVNH9ABAUvmu0"
    private let gid = "0" // your tab's gid
    
    // Polling
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
    
    // Fetches entire CSV, extracts row 1
    private func fetchFirstRowFromCSV() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: csvURL())
            guard let csv = String(data: data, encoding: .utf8) else { return }
            parseFirstRow(csv)
            updateTimestamp()
        } catch {
            // You could surface errors in UI if you want
            // print("CSV fetch failed:", error)
        }
    }
    
    // Minimal CSV split for first row; handles quoted cells "a,b"
    // Parse the FIRST CSV RECORD (row 1), respecting quotes, commas, and embedded newlines.
    private func parseFirstRecord(_ csv: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuotes = false
        var i = csv.startIndex

        while i < csv.endIndex {
            let ch = csv[i]

            if ch == "\"" {
                // Handle "" inside a quoted field -> literal "
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
                // End of first record (row 1)
                break
            } else {
                cur.append(ch)
            }

            i = csv.index(after: i)
        }
        out.append(cur)

        // Trim surrounding quotes and whitespace from each field
        return out.map {
            var s = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 {
                s.removeFirst(); s.removeLast()
            }
            return s.replacingOccurrences(of: "\"\"", with: "\"")
        }
    }

    // Use this instead of splitting the first line
    private func parseFirstRow(_ csvString: String) {
        let cells = parseFirstRecord(csvString)
        DispatchQueue.main.async {
            self.a1Text = cells.first ?? ""   // will include \n if present
            self.firstRow = cells
        }
    }

    
    // Basic CSV parser for a single line with quotes
    private func splitCSVLine<S: StringProtocol>(_ line: S) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuotes = false
        
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\"" {
                // Toggle quotes, or handle escaped quote ""
                let next = line.index(after: i)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    cur.append("\"")
                    i = next
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                out.append(cur)
                cur.removeAll(keepingCapacity: true)
            } else {
                cur.append(ch)
            }
            i = line.index(after: i)
        }
        out.append(cur)
        // Trim outer quotes and whitespace
        return out.map {
            var s = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 {
                s.removeFirst(); s.removeLast()
            }
            return s
        }
    }
}
