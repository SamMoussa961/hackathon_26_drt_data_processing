import Foundation

struct SwapRecommendation: Identifiable {
    let id = UUID()
    let busAlias: String
    let currentRoute: String
    let proposedRoute: String
    let wearScore: Double
    let currentStress: Double
    let proposedStress: Double
    let swapScore: Double
    let estimatedAnnualSavingCAD: Double  // illustrative placeholder
    let wearDelta: Double                 // outgoing wear − incoming wear (positive = improvement)
    let significance: String              // "HIGH" | "MEDIUM"
}
