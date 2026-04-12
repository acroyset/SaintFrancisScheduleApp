//
//  FullscreenYouTubePlayerView.swift
//  Schedule
//

import SwiftUI
import WebKit

struct FullscreenYouTubePlayerView: View {
    let video: LancerLiveVideo
    let primaryColor: Color
    let tertiaryColor: Color

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            YouTubeEmbedWebView(video: video)
                .ignoresSafeArea()
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                        .foregroundStyle(tertiaryColor.highContrastTextColor())
                    }
                }
                .toolbarBackground(.black, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

private struct YouTubeEmbedWebView: UIViewRepresentable {
    let video: LancerLiveVideo

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let origin = appOrigin
        let url = video.embedURL(origin: origin)

        var request = URLRequest(url: url)
        request.setValue(origin, forHTTPHeaderField: "Referer")

        if webView.url != request.url {
            webView.load(request)
        }
    }

    private var appOrigin: String {
        let bundleID = (Bundle.main.bundleIdentifier ?? "com.schedule.app").lowercased()
        return "https://\(bundleID)"
    }
}
