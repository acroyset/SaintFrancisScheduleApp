//
//  ScheduleWidgetBundle.swift
//  ScheduleWidget
//
//  Created by Andreas Royset on 8/16/25.
//

import WidgetKit
import SwiftUI

@main
struct ScheduleWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScheduleWidget()
        ScheduleWidgetControl()
        ScheduleWidgetLiveActivity()
    }
}
