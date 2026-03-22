//
//  HTMLRenderer.swift
//  Schedule
//
//  Created by Andreas Royset on 1/21/26.
//

import SwiftUI
import WebKit

struct ThemedAutoHeightWebView: UIViewRepresentable {
    let html: String
    let isDarkTheme: Bool      
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()

        // Transparent
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false

        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // ✅ Prevent reload loops (height updates trigger SwiftUI updates)
        let signature = "\(isDarkTheme)|\(html.hashValue)"
        guard context.coordinator.lastLoadedSignature != signature else { return }
        context.coordinator.lastLoadedSignature = signature

        let textHex = isDarkTheme ? "#F0F0F0" : "#0F0F0F"

        // Strong CSS overrides for email HTML (tables/inline styles)
        let wrappedHTML = """
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
              html, body { margin:0; padding:0; background: transparent !important; }
              body, body * {
                background: transparent !important;
                color: \(textHex) !important;
                -webkit-text-fill-color: \(textHex) !important;
              }
              a, a:visited { color: \(textHex) !important; text-decoration: underline; }
              img { max-width: 100%; height: auto; }
            </style>
          </head>
          <body>\(html)</body>
        </html>
        """

        webView.loadHTMLString(wrappedHTML, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: ThemedAutoHeightWebView
        var lastLoadedSignature: String?

        init(_ parent: ThemedAutoHeightWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateHeight(webView)

            // Some email HTML settles after a moment (images/tables)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.updateHeight(webView)
            }
        }

        private func updateHeight(_ webView: WKWebView) {
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                guard let self, let h = result as? CGFloat else { return }
                DispatchQueue.main.async {
                    if abs(self.parent.height - h) > 1 { self.parent.height = h }
                }
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        // Handles target="_blank"
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                UIApplication.shared.open(url)
            }
            return nil
        }
    }
}
