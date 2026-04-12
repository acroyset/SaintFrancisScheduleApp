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
    
    @StateObject var store = NewsStore()
    
    @State private var webHeight: CGFloat = 1
    @State private var fullscreenVideo: LancerLiveVideo?
    @State private var headerHeight: CGFloat = 0
    
    var body: some View {
        ZStack {
            ScrollView {
                Color.clear.frame(height: headerHeight + 4)
                
                VStack(alignment: .leading, spacing: 12) {
                    contentView
                    
                    Text("Last updated: \(store.lastUpdatedString)")
                        .font(.footnote)
                        .foregroundStyle(TertiaryColor.highContrastTextColor())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .padding()
                
                Color.clear.frame(height: iPad ? 60 : 50)
            }
            .mask {
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.05),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            
            VStack {
                headerView
                
                Spacer()
            }
        }
        .task { await store.startPolling() }
        .onDisappear { store.stopPolling() }
        .fullScreenCover(item: $fullscreenVideo) { video in
            FullscreenYouTubePlayerView(
                video: video,
                primaryColor: PrimaryColor,
                tertiaryColor: TertiaryColor
            )
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if store.isLoading && store.latestVideo == nil && store.htmlContent.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(PrimaryColor)

                Text("Loading \(store.selectedSource.title)...")
                    .appThemeFont(.secondary, size: 16, weight: .medium)
                    .foregroundStyle(TertiaryColor.highContrastTextColor())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(SecondaryColor)
            )
        } else if let errorMessage = store.errorMessage, store.latestVideo == nil, store.htmlContent.isEmpty {
            Text(errorMessage)
                .appThemeFont(.secondary, size: 16, weight: .medium)
                .foregroundStyle(TertiaryColor.highContrastTextColor())
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(SecondaryColor)
                )
        } else if let video = store.latestVideo {
            LancerLiveVideoCard(
                video: video,
                primaryColor: PrimaryColor,
                secondaryColor: SecondaryColor,
                tertiaryColor: TertiaryColor,
                onFullscreen: {
                    fullscreenVideo = video
                }
            )
        } else {
            ThemedAutoHeightWebView(
                html: store.htmlContent,
                isDarkTheme: TertiaryColor.luminance() < 0.5,
                height: $webHeight,
            )
            .frame(height: webHeight)
            .background(Color.clear)
        }
    }

    private var sourceTabs: some View {
        NewsSourceTabs(
            selectedSource: $store.selectedSource,
            primaryColor: PrimaryColor,
            secondaryColor: SecondaryColor,
            tertiaryColor: TertiaryColor,
            onSelect: {
                store.refreshForSelectionChange()
            }
        )
    }

    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: 8) {
            titleSection
            sourceTabs
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        headerHeight = geo.size.height
                    }
                    .onChange(of: geo.size.height) { _, newHeight in
                        headerHeight = newHeight
                    }
            }
        )
    }

    @ViewBuilder
    private var titleSection: some View {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            headerTitle
                .padding(.vertical, iPad ? 12 : 10)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .glassEffect()
        } else {
            headerTitle
                .padding(.vertical, iPad ? 12 : 10)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(SecondaryColor)
                )
        }
    }

    private var headerTitle: some View {
        Text("Saint Francis News")
            .font(.system(
                size: iPad ? 34 : 22,
                weight: .bold,
                design: .monospaced
            ))
            .foregroundStyle(PrimaryColor)
    }
}
