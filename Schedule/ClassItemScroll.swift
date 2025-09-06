//
//  ClassItemScroll.swift
//  Schedule
//
//  Created by Andreas Royset on 9/5/25.
//

import Foundation
import SwiftUI

struct ClassItemScroll: View {
    var scheduleLines: [ScheduleLine]
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    var note: String
    var dayCode: String
    var output: String
    @Binding var scrollTarget: Int?
    
    // Configuration for proportional sizing
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if !output.isEmpty && scheduleLines.isEmpty {
                    Text(output)
                        .font(.system(
                            size: iPad ? 35 : 17,
                            design: .monospaced
                        ))
                        .foregroundColor(PrimaryColor)
                }
                
                ForEach(Array(scheduleLines.enumerated()), id: \.0) { i, line in
                    rowView(
                        line,
                        note : note,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                    .id(i)
                }
            }
            .padding(.horizontal)
        }
        .id(dayCode)
        .scrollPosition(id: $scrollTarget, anchor: .center)
    }
}
