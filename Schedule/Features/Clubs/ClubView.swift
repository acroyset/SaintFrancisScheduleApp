//
//  ClubView.swift
//  Schedule
//
//  Created by Andreas Royset on 9/5/25.
//

import Foundation
import SwiftUI

struct ClubView: View {
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var body: some View {
        VStack {
            Text("Clubs")
                .font(.system(
                    size: iPad ? 34 : 22,
                    weight: .bold,
                    design: .monospaced
                ))
                .padding(12)
                .foregroundStyle(PrimaryColor.opacity(1))
            
            Divider()
            
            ScrollView {
                Text("Coming Soon")
                    .font(.system(size: iPad ? 20 : 12, weight: .semibold))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SecondaryColor)
                    .foregroundStyle(PrimaryColor)
                    .cornerRadius(8)
            }
            
            Divider()
            
            Text("Email acroyset@gmail.com if you want to put your club on here. \n\nLast updated: NA") //<-------- add last updated
                .font(.footnote)
                .foregroundStyle(TertiaryColor.highContrastTextColor())
                .frame(maxWidth: .infinity, alignment: .leading)
            
            .padding()
        }
        //.task { await store.startPolling() }   // begin 10s polling
        //.onDisappear { store.stopPolling() }   // stop when view goes away
    }
}
