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
        VStack(spacing: 0) {
            Text(dayInfo?.name ?? "Error")
                .font(.system(
                    size: iPad ? 60 : 35,
                    weight: .bold))
                .foregroundColor(TertiaryColor)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(12)
        }
    }
}
