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
            if #available(iOS 26.0, *) {
                Text(dayInfo?.name ?? "No Classes")
                    .font(.system(
                        size: iPad ? 60 : 35,
                        weight: .bold))
                    .foregroundColor(TertiaryColor)
                    .padding(iPad ? 16 : 12)
            } else {
                Text(dayInfo?.name ?? "No Classes")
                    .font(.system(
                        size: iPad ? 60 : 35,
                        weight: .bold))
                    .foregroundColor(PrimaryColor)
                    .padding(iPad ? 16 : 12)
            }
        }
    }
}
