//
//  ClassProgressBar.swift
//  ScheduleWidgetExtension
//
//  Created by Andreas Royset on 9/4/25.
//

import Foundation
import SwiftUI

struct ClassProgressBar: View {
    var progress: Double      // 0...1
    var active: Bool          // highlight when current class
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color

    var body: some View {
        if active{
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(PrimaryColor.mix(with: .black, by: 0.4))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(TertiaryColor)
                        .frame(height: max(0, geo.size.height * progress))
                }
            }
        }
    }
}
