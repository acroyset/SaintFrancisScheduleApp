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
    
    @State private var webHeight: CGFloat = 1
    
    var body: some View {
        ZStack {
            ScrollView {
                Color.clear.frame(height: iPad ? 60 : 50)
                
                VStack(alignment: .leading, spacing: 12) {
                    ThemedAutoHeightWebView(
                        html: store.htmlContent,
                        isDarkTheme: TertiaryColor.luminance() < 0.5,
                        height: $webHeight,
                    )
                    .frame(height: webHeight)
                    .background(Color.clear) // SwiftUI side
                    
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
                if #available(iOS 26.0, *) {
                    Text("Saint Francis News")
                        .font(.system(
                            size: iPad ? 34 : 22,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .padding(iPad ? 16 : 12)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(PrimaryColor)
                        .glassEffect()
                } else {
                    Text("Saint Francis News")
                        .font(.system(
                            size: iPad ? 34 : 22,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .padding(12)
                        .foregroundStyle(PrimaryColor)
                }
                
                Spacer()
            }
        }
        .task { await store.startPolling() }
        .onDisappear { store.stopPolling() }
    }
}
