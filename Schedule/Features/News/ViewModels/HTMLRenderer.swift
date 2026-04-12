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
        context.coordinator.parent = self

        // ✅ Prevent reload loops (height updates trigger SwiftUI updates)
        let signature = "\(isDarkTheme)|\(html.hashValue)"
        if context.coordinator.lastLoadedSignature == signature {
            context.coordinator.updateHeight(webView)
            return
        }
        context.coordinator.lastLoadedSignature = signature

        let textHex = isDarkTheme ? "#F0F0F0" : "#0F0F0F"

        // Strong CSS overrides for email HTML so it reads more like app content.
        let wrappedHTML = """
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
              :root {
                color-scheme: \(isDarkTheme ? "dark" : "light");
              }
              html, body {
                margin: 0;
                padding: 0;
                background: transparent !important;
              }
              body, body * {
                background: transparent !important;
                color: \(textHex) !important;
                -webkit-text-fill-color: \(textHex) !important;
              }
              body {
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
                font-size: 16px !important;
                line-height: 1.45 !important;
                word-break: break-word;
                overflow-wrap: anywhere;
              }
              p, div, li, td, th {
                font-size: 16px !important;
                line-height: 1.45 !important;
              }
              p, ul, ol, table, blockquote {
                margin-top: 0 !important;
                margin-bottom: 0.7em !important;
              }
              ul, ol {
                padding-left: 1.2em !important;
              }
              h1, h2, h3, h4, h5, h6 {
                margin-top: 0.9em !important;
                margin-bottom: 0.45em !important;
                line-height: 1.2 !important;
              }
              h1 { font-size: 1.55em !important; }
              h2 { font-size: 1.35em !important; }
              h3 { font-size: 1.18em !important; }
              a, a:visited {
                color: \(textHex) !important;
                text-decoration: underline;
              }
              img {
                max-width: 100%;
                height: auto;
                border-radius: 14px;
              }
              table {
                width: 100% !important;
                border-collapse: collapse !important;
                table-layout: fixed;
              }
              td, th {
                padding: 6px 8px !important;
                vertical-align: top;
              }
              br + br {
                display: none;
              }
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

        func updateHeight(_ webView: WKWebView) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { [weak self] result, _ in
                guard let self else { return }
                let heightValue: CGFloat?
                if let number = result as? NSNumber {
                    heightValue = CGFloat(truncating: number)
                } else {
                    heightValue = nil
                }
                guard let h = heightValue else { return }
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
