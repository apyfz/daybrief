import BriefRender
import DaybriefCore
import DaybriefWidgetUI
import SwiftUI
import WidgetKit

// MARK: - Root router

/// Routes the timeline entry to the size-specific layout (in `DaybriefWidgetUI`). The
/// widget is **view-only**: a tap anywhere brings the app forward (`daybrief://open`) so
/// the reader can act from the menu-bar panel — the widget never opens a window itself.
struct BriefWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BriefEntry

    var body: some View {
        Group {
            if let brief = entry.brief {
                let vm = BriefRenderer().viewModel(brief)
                switch family {
                case .systemSmall:
                    SmallBriefView(brief: brief, vm: vm, heroPNG: entry.heroPNG)
                case .systemLarge:
                    LargeBriefView(brief: brief, vm: vm, heroPNG: entry.heroPNG)
                case .systemExtraLarge:
                    ExtraLargeBriefView(brief: brief, vm: vm, heroPNG: entry.heroPNG)
                default:
                    MediumBriefView(brief: brief, vm: vm, heroPNG: entry.heroPNG)
                }
            } else {
                WidgetEmptyView()
            }
        }
        .widgetURL(URL(string: "daybrief://open"))
    }
}
