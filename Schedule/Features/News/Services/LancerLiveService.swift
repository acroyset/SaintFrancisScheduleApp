//
//  LancerLiveService.swift
//  Schedule
//

import Foundation

struct LancerLiveService {
    private let handleURL = URL(string: "https://www.youtube.com/@sflancerlive/videos")!
    private let channelIDCacheKey = "LancerLiveChannelID"

    func fetchLatestVideo() async throws -> LancerLiveVideo {
        var lastError: Error?

        for feedURL in await feedURLs() {
            do {
                let xml = try await fetchText(from: feedURL)
                guard let video = parseLatestVideo(from: xml) else {
                    throw URLError(.cannotParseResponse)
                }
                return video
            } catch {
                lastError = error
                print("⚠️ Lancer Live feed failed for \(feedURL.absoluteString): \(error)")
            }
        }

        do {
            let html = try await fetchText(from: handleURL)
            guard let video = parseLatestVideoFromChannelPage(html) else {
                throw URLError(.cannotParseResponse)
            }
            return video
        } catch {
            lastError = error
            print("⚠️ Lancer Live channel page fallback failed: \(error)")
        }

        throw lastError ?? URLError(.badServerResponse)
    }

    private func feedURLs() async -> [URL] {
        var urls: [URL] = []

        do {
            let channelID = try await resolveChannelID()
            UserDefaults.standard.set(channelID, forKey: channelIDCacheKey)
            urls.append(channelFeedURL(channelID: channelID))
        } catch {
            print("⚠️ Lancer Live channel lookup failed: \(error)")
            if let cachedChannelID = UserDefaults.standard.string(forKey: channelIDCacheKey) {
                urls.append(channelFeedURL(channelID: cachedChannelID))
            }
        }

        // Some YouTube handles also work as legacy user feeds. Keep this as a
        // cheap fallback when the handle page changes or is rate limited.
        if let userFeed = URL(string: "https://www.youtube.com/feeds/videos.xml?user=sflancerlive") {
            urls.append(userFeed)
        }

        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    private func channelFeedURL(channelID: String) -> URL {
        URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)")!
    }

    private func resolveChannelID() async throws -> String {
        let html = try await fetchText(from: handleURL)

        let patterns = [
            #"<link rel=\"alternate\" type=\"application/rss\+xml\" title=\"RSS\" href=\"https://www\.youtube\.com/feeds/videos\.xml\?channel_id=(UC[^"]+)\""#,
            #"<link rel=\"canonical\" href=\"https://www\.youtube\.com/channel/(UC[^"]+)\""#,
            #"<meta itemprop=\"identifier\" content=\"(UC[^"]+)\""#,
            #"<meta itemprop=\"channelId\" content=\"(UC[^"]+)\""#,
            #""browseId":"(UC[^"]+)""#,
            #""externalId":"(UC[^"]+)""#,
            #""channelId":"(UC[^"]+)""#,
            #"https://www\.youtube\.com/channel/(UC[^"\/?]+)"#,
            #"https:\/\/www\.youtube\.com\/channel\/(UC[^"\/?]+)"#,
            #"channel\/(UC[\w-]+)"#
        ]

        for pattern in patterns {
            if let value = firstMatch(in: html, pattern: pattern) {
                return value
            }
        }

        throw URLError(.badServerResponse)
    }

    private func fetchText(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return String(decoding: data, as: UTF8.self)
    }

    private func parseLatestVideo(from xml: String) -> LancerLiveVideo? {
        guard let entry = firstMatch(in: xml, pattern: #"(?s)<entry>(.*?)</entry>"#) else {
            return nil
        }

        guard
            let title = firstMatch(in: entry, pattern: #"<title>(.*?)</title>"#),
            let videoID = firstMatch(in: entry, pattern: #"<yt:videoId>(.*?)</yt:videoId>"#),
            let urlString = firstMatch(in: entry, pattern: #"<link rel=\"alternate\" href=\"(.*?)\"\s*/>"#),
            let thumbnailString = firstMatch(in: entry, pattern: #"<media:thumbnail url=\"(.*?)\""#),
            let watchURL = URL(string: decodeXMLEntities(urlString)),
            let thumbnailURL = URL(string: decodeXMLEntities(thumbnailString))
        else {
            return nil
        }

        let publishedRaw = firstMatch(in: entry, pattern: #"<published>(.*?)</published>"#) ?? ""

        return LancerLiveVideo(
            id: decodeXMLEntities(videoID),
            title: decodeXMLEntities(title),
            watchURL: watchURL,
            thumbnailURL: thumbnailURL,
            publishedAt: parseDate(publishedRaw)
        )
    }

    private func parseLatestVideoFromChannelPage(_ html: String) -> LancerLiveVideo? {
        guard
            let videoMatch = firstGroups(
                in: html,
                pattern: #"(?s)"videoRenderer":\{"videoId":"([^"]+)".*?"title":\{"runs":\[\{"text":"((?:\\.|[^"\\])*)""#
            )
        else {
            return nil
        }

        guard
            videoMatch.count == 2,
            let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoMatch[0])"),
            let thumbnailURL = URL(string: "https://i.ytimg.com/vi/\(videoMatch[0])/hqdefault.jpg")
        else {
            return nil
        }

        return LancerLiveVideo(
            id: videoMatch[0],
            title: decodeJSONEscapes(videoMatch[1]),
            watchURL: watchURL,
            thumbnailURL: thumbnailURL,
            publishedAt: nil
        )
    }

    private func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[captureRange])
    }

    private func firstGroups(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1 else {
            return nil
        }

        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let captureRange = Range(match.range(at: index), in: text) else {
                return nil
            }
            groups.append(String(text[captureRange]))
        }
        return groups
    }

    private func decodeJSONEscapes(_ text: String) -> String {
        let quoted = "\"\(text)\""
        guard let data = quoted.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else {
            return text
        }

        return decoded
    }

    private func decodeXMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
