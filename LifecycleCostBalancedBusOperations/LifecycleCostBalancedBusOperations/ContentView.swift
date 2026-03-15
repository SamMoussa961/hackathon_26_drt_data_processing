import SwiftUI

// MARK: - Shared colour helper

extension Double {
    var scoreColor: Color {
        self > 70 ? .red : self > 40 ? .orange : .green
    }
}

// MARK: - Shared score bar

struct ScoreBar: View {
    let score: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(score.scoreColor)
                    .frame(width: max(2, geo.size.width * score / 100))
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Sidebar destinations

enum SidebarItem: String, CaseIterable, Identifiable {
    case fleet        = "Fleet Health"
    case routes       = "Route Stress"
    case swaps        = "Swap Engine"
    case presentation = "Presentation"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fleet:        return "bus.fill"
        case .routes:       return "map.fill"
        case .swaps:        return "arrow.2.squarepath"
        case .presentation: return "chart.bar.doc.horizontal.fill"
        }
    }
}

// MARK: - Root layout

struct ContentView: View {
    @State private var selection: SidebarItem? = .fleet

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("DRT Fleet")
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 220)
        } detail: {
            switch selection {
            case .fleet:        FleetHealthView()
            case .routes:       RouteStressView()
            case .swaps:        SwapEngineView()
            case .presentation: PresentationView()
            case nil:           FleetHealthView()
            }
        }
    }
}

#Preview {
    ContentView()
}
