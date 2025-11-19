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
                .foregroundStyle(TertiaryColor.highContrastTextColor())
                .frame(maxWidth: .infinity, alignment: .leading)
            
            .padding()
        }
        .task { await store.startPolling() }   // begin 10s polling
        .onDisappear { store.stopPolling() }   // stop when view goes away
    }
}
