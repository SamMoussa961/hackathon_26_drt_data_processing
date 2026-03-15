import Foundation

struct Bus: Identifiable, Hashable {
    var id: String { alias }
    let alias: String
    let lastreading: Double   // km at last PM reading
    let unitstogo: Double     // km remaining until next PM trigger
    let unitslate: Double     // km overdue
    let dayslate: Double      // calendar days overdue
    let wearScore: Double     // 0–100, higher = more worn
    let currentRoute: String? // most frequent route (rider-feedback proxy)

    func hash(into hasher: inout Hasher) { hasher.combine(alias) }
    static func == (lhs: Bus, rhs: Bus) -> Bool { lhs.alias == rhs.alias }
}
