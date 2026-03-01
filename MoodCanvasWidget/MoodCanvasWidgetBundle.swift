import WidgetKit
import SwiftUI

@main
struct MoodCanvasWidgetBundle: WidgetBundle {
    var body: some Widget {
        MoodCanvasBFFMediumWidget()    // Friends/Family ≤ 3 members — 4×2
        MoodCanvasBFFWidget()          // Friends/Family 4+ members — 4×4
        MoodCanvasWidget()             // Couple — 4×2
    }
}
