//
//  NewsStore.swift
//  Schedule
//

import Foundation
import SwiftUI

@MainActor
final class NewsStore: ObservableObject {
    @Published var selectedSource: NewsSource = .dailyAnnouncements
    @Published var lastUpdatedString: String = "—"
    @Published var htmlContent: String = ""
    @Published var latestVideo: LancerLiveVideo?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    private let announcementsService = DailyAnnouncementsService()
    private let lancerLiveService = LancerLiveService()
    private let refreshSeconds: UInt64 = 30

    private var pollTask: Task<Void, Never>?
    private var currentLoadID = UUID()
    private var cachedAnnouncementsHTML: String = ""
    private var cachedLancerLiveVideo: LancerLiveVideo?

    func startPolling() async {
        stopPolling()
        pollTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.fetchSelectedSource()
                try? await Task.sleep(nanoseconds: refreshSeconds * 1_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshForSelectionChange() {
        Task { [weak self] in
            await self?.fetchSelectedSource()
        }
    }

    private func fetchSelectedSource() async {
        let requestedSource = selectedSource
        let loadID = UUID()

        currentLoadID = loadID
        isLoading = true
        errorMessage = nil

        switch requestedSource {
        case .dailyAnnouncements:
            latestVideo = nil
            if !cachedAnnouncementsHTML.isEmpty {
                htmlContent = cachedAnnouncementsHTML
            }
            await fetchDailyAnnouncements(loadID: loadID, source: requestedSource)
        case .lancerLive:
            htmlContent = ""
            if let cachedLancerLiveVideo {
                latestVideo = cachedLancerLiveVideo
            } else {
                latestVideo = nil
            }
            await fetchLancerLive(loadID: loadID, source: requestedSource)
        }
    }

    private func fetchDailyAnnouncements(loadID: UUID, source: NewsSource) async {
        do {
            let html = try await announcementsService.fetchHTML()
            guard shouldApply(loadID: loadID, source: source) else { return }

            htmlContent = html
            cachedAnnouncementsHTML = html
            isLoading = false
            updateTimestamp()
        } catch {
            guard shouldApply(loadID: loadID, source: source) else { return }

            isLoading = false
            if cachedAnnouncementsHTML.isEmpty {
                htmlContent = ""
                errorMessage = "Couldn’t load Daily Announcements right now."
            } else {
                htmlContent = cachedAnnouncementsHTML
                errorMessage = "Showing the last loaded Daily Announcements."
            }
        }
    }

    private func fetchLancerLive(loadID: UUID, source: NewsSource) async {
        var lastError: Error?

        for attempt in 1...3 {
            guard shouldApply(loadID: loadID, source: source) else { return }

            do {
                let video = try await lancerLiveService.fetchLatestVideo()
                guard shouldApply(loadID: loadID, source: source) else { return }

                latestVideo = video
                cachedLancerLiveVideo = video
                isLoading = false
                updateTimestamp()
                return
            } catch {
                lastError = error
                guard attempt < 3 else { break }
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 700_000_000)
            }
        }

        if let lastError {
            print("⚠️ Lancer Live failed after retries: \(lastError)")
        }

        guard shouldApply(loadID: loadID, source: source) else { return }

        isLoading = false
        if let cachedLancerLiveVideo {
            latestVideo = cachedLancerLiveVideo
            errorMessage = "Showing the last loaded Lancer Live video."
        } else {
            latestVideo = nil
            errorMessage = "Couldn’t load the latest Lancer Live video right now."
        }
    }

    private func shouldApply(loadID: UUID, source: NewsSource) -> Bool {
        currentLoadID == loadID && selectedSource == source
    }

    private func updateTimestamp() {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        lastUpdatedString = formatter.string(from: Date())
    }
}
