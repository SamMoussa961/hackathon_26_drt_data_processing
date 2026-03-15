import Foundation

struct Route: Identifiable, Hashable {
    var id: String { routeId }
    let routeId: String
    let routeShortName: String
    let stopCount: Int
    let shapeDistanceKm: Double
    let avgTapsPerStop: Double
    let stressScore: Double    // 0–100, higher = more stressful

    func hash(into hasher: inout Hasher) { hasher.combine(routeId) }
    static func == (lhs: Route, rhs: Route) -> Bool { lhs.routeId == rhs.routeId }
}
