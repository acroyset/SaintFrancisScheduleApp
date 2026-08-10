//
//  AthleticsService.swift
//  Schedule
//

import Foundation

enum AthleticsTextSanitizer {
    static func sanitize(_ value: String) -> String {
        let correctedSpelling = [
            ("Aqautic", "Aquatic"),
            ("SemiFinal", "Semifinal")
        ].reduce(value) { result, replacement in
            result.replacingOccurrences(
                of: replacement.0,
                with: replacement.1,
                options: .caseInsensitive
            )
        }

        let correctedLocation = correctedSpelling.replacingOccurrences(
            of: #"\bSanta Clara,\s*Ca\b"#,
            with: "Santa Clara, CA",
            options: [.regularExpression, .caseInsensitive]
        )

        return correctedLocation
            .replacingOccurrences(
                of: #"[ \t]{2,}"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AthleticsService {
    private let homeURL = URL(string: "https://sfhsathletics.com")!

    func fetchSchedule() async throws -> AthleticsSchedule {
        let html = try await fetchHomepage()

        let upcoming = try extractEvents(type: "events", from: html)
        let recent = try extractEvents(type: "results", from: html)

        return AthleticsSchedule(upcoming: upcoming, recent: recent)
    }

    private func fetchHomepage() async throws -> String {
        var request = URLRequest(url: homeURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return String(decoding: data, as: UTF8.self)
    }

    private func extractEvents(type: String, from html: String) throws -> [AthleticsEvent] {
        let components = extractComponentJSON(from: html)
        let decoder = JSONDecoder()

        for json in components {
            guard let data = json.data(using: .utf8),
                  let component = try? decoder.decode(SidearmComponent.self, from: data),
                  component.type == type else {
                continue
            }

            return component.data.map { $0.athleticsEvent }
        }

        throw URLError(.cannotParseResponse)
    }

    private func extractComponentJSON(from html: String) -> [String] {
        let marker = "var obj = "
        var results: [String] = []
        var searchStart = html.startIndex

        while let markerRange = html.range(of: marker, range: searchStart..<html.endIndex) {
            var index = markerRange.upperBound
            guard index < html.endIndex, html[index] == "{" else {
                searchStart = markerRange.upperBound
                continue
            }

            let objectStart = index
            var depth = 0
            var insideString = false
            var isEscaped = false

            while index < html.endIndex {
                let character = html[index]

                if insideString {
                    if isEscaped {
                        isEscaped = false
                    } else if character == "\\" {
                        isEscaped = true
                    } else if character == "\"" {
                        insideString = false
                    }
                } else if character == "\"" {
                    insideString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        let objectEnd = html.index(after: index)
                        results.append(String(html[objectStart..<objectEnd]))
                        searchStart = objectEnd
                        break
                    }
                }

                index = html.index(after: index)
            }

            if index >= html.endIndex {
                break
            }
        }

        return results
    }
}

private struct SidearmComponent: Decodable {
    let type: String
    let data: [SidearmEvent]
}

private struct SidearmEvent: Decodable {
    let id: Int
    let date: String?
    let time: String?
    let tbd: Bool?
    let locationIndicator: String?
    let location: String?
    let sport: SidearmSport?
    let schedule: SidearmSchedule?
    let opponent: SidearmOpponent?
    let result: SidearmResult?

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case time
        case tbd
        case locationIndicator = "location_indicator"
        case location
        case sport
        case schedule
        case opponent
        case result
    }

    var athleticsEvent: AthleticsEvent {
        let parsedDate = parseDate(date)

        return AthleticsEvent(
            id: id,
            date: parsedDate,
            dateText: formatDate(parsedDate, fallback: date),
            time: AthleticsTextSanitizer.sanitize(time ?? ""),
            sportTitle: AthleticsTextSanitizer.sanitize(
                sport?.title ?? "Saint Francis Athletics"
            ),
            opponentTitle: AthleticsTextSanitizer.sanitize(opponent?.title ?? "TBD"),
            location: AthleticsTextSanitizer.sanitize(location ?? ""),
            locationIndicator: locationIndicator ?? "",
            resultStatus: result?.status,
            teamScore: result?.teamScore,
            opponentScore: result?.opponentScore,
            scheduleURL: schedule?.url.flatMap(URL.init(string:)),
            isTBD: tbd ?? false
        )
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")

        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private func formatDate(_ date: Date?, fallback: String?) -> String {
        guard let date else {
            return fallback ?? ""
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

private struct SidearmSport: Decodable {
    let title: String?
}

private struct SidearmSchedule: Decodable {
    let url: String?
}

private struct SidearmOpponent: Decodable {
    let title: String?
}

private struct SidearmResult: Decodable {
    let status: String?
    let teamScore: String?
    let opponentScore: String?

    enum CodingKeys: String, CodingKey {
        case status
        case teamScore = "team_score"
        case opponentScore = "opponent_score"
    }
}
