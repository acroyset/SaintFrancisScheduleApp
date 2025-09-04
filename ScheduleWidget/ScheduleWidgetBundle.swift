//
//  ScheduleWidgetBundle.swift
//  ScheduleWidget
//
//  Created by Andreas Royset on 9/4/25.
//

import WidgetKit
import SwiftUI

struct ScheduleWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScheduleWidget()
        ScheduleWidgetControl()
        ScheduleWidgetLiveActivity()
    }
}
