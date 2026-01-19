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
        ZStack{
            
            ScrollView {
                
                Color.clear.frame(height: iPad ? 60 : 50)
                
                Text(store.a1Text.isEmpty ? "—" : store.a1Text)
                    .font(.system(size: iPad ? 22 : 18, weight: .semibold))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SecondaryColor)
                    .foregroundStyle(PrimaryColor)
                    .cornerRadius(8)
                
                Text("Email acroyset@gmail.com if you want to put your announcement on here. \n\nLast updated: \(store.lastUpdatedString)")
                    .font(.footnote)
                    .foregroundStyle(TertiaryColor.highContrastTextColor())
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                    .padding()
                
                Color.clear.frame(height: iPad ? 60 : 50)
                
                
            }
            .mask{
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
        .task { await store.startPolling() }   // begin 10s polling
        .onDisappear { store.stopPolling() }   // stop when view goes away
    }
}
