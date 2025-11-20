//
//  DayHeaderView.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI

struct DayHeaderView: View {
    let dayInfo: Day?
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    
    var body: some View {
        if let day = dayInfo {
            VStack(spacing: 0) {
                Text(day.name)
                    .font(.system(
                        size: iPad ? 60 : 35,
                        weight: .bold))
                    .foregroundColor(PrimaryColor)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(SecondaryColor)
                    .cornerRadius(8)
            }
            .padding(.horizontal)
        } else {
            VStack(spacing: 0) {
                Text(" ")
                    .font(.system(
                        size: iPad ? 60 : 35,
                        weight: .bold))
                    .foregroundColor(PrimaryColor)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(SecondaryColor)
                    .cornerRadius(8)
            }
            .padding(.horizontal)
        }
    }
}
