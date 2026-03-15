import SwiftUI

struct FleetHealthView: View {
    @State private var buses:    [Bus] = []
    @State private var swapRecs: [SwapRecommendation] = []
    @State private var selected: Bus.ID?
    @State private var detailBus: Bus?

    var body: some View {
        Table(buses, selection: $selected) {
            TableColumn("Bus") { bus in
                Text(bus.alias).font(.body.monospacedDigit())
            }
            .width(min: 70, ideal: 80)

            TableColumn("Wear Score") { bus in
                HStack(spacing: 8) {
                    ScoreBar(score: bus.wearScore).frame(width: 80)
                    Text(String(format: "%.0f", bus.wearScore))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(bus.wearScore.scoreColor)
                        .frame(width: 28, alignment: .trailing)
                }
            }
            .width(min: 120, ideal: 130)

            TableColumn("Route") { bus in
                Text(bus.currentRoute.map { "Route \($0)" } ?? "—")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 100)

            TableColumn("Days Late") { bus in
                Text(bus.dayslate > 0 ? String(format: "%.0f d", bus.dayslate) : "—")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(bus.dayslate > 0 ? .red : .secondary)
            }
            .width(min: 80, ideal: 90)

            TableColumn("Km to Next PM") { bus in
                Text(String(format: "%.0f km", bus.unitstogo))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(bus.unitstogo < 0 ? .red : .primary)
            }
            .width(min: 110, ideal: 120)
        }
        .navigationTitle("Fleet Health")
        .navigationSubtitle("\(buses.count) buses")
        .onChange(of: selected) { _, newID in
            detailBus = buses.first { $0.id == newID }
        }
        .sheet(item: $detailBus) { bus in
            BusDetailSheet(bus: bus,
                           swapRec: swapRecs.first { $0.busAlias == bus.alias })
        }
        .task {
            buses    = DatabaseManager.shared.fetchBuses()
            swapRecs = DatabaseManager.shared.fetchSwapRecs()
        }
    }
}

// MARK: - Bus detail sheet

private struct BusDetailSheet: View {
    let bus: Bus
    let swapRec: SwapRecommendation?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Bus \(bus.alias)").font(.largeTitle.bold())
                    Text("Route assignment based on rider-feedback proxy data")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(format: "Wear Score: %.1f / 100", bus.wearScore))
                                .font(.title2.bold()).foregroundStyle(bus.wearScore.scoreColor)
                            ScoreBar(score: bus.wearScore).frame(width: 200)
                        }
                        Spacer()
                    }

                    GroupBox("PM Status") {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                            pmRow("Last Reading",  String(format: "%.0f km", bus.lastreading))
                            pmRow("Until Next PM", String(format: "%.0f km", bus.unitstogo),
                                  color: bus.unitstogo < 0 ? .red : .primary)
                            pmRow("Units Overdue", String(format: "%.0f km", bus.unitslate),
                                  color: bus.unitslate > 0 ? .orange : .primary)
                            pmRow("Days Overdue",  String(format: "%.0f days", bus.dayslate),
                                  color: bus.dayslate > 0 ? .red : .primary)
                            pmRow("Current Route", bus.currentRoute ?? "Unknown")
                        }
                        .padding(4)
                    }

                    if let rec = swapRec {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Swap Recommended", systemImage: "arrow.2.squarepath")
                                    .font(.headline).foregroundStyle(.orange)

                                HStack(spacing: 16) {
                                    stressChip("Route \(rec.currentRoute)",  stress: rec.currentStress,  label: "current")
                                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                    stressChip("Route \(rec.proposedRoute)", stress: rec.proposedStress, label: "proposed")
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text("Wear Δ").font(.caption).foregroundStyle(.secondary)
                                        Text(String(format: "+%.1f pts", rec.wearDelta))
                                            .font(.title3.bold()).foregroundStyle(.green)
                                        Text(rec.significance)
                                            .font(.caption.bold())
                                            .padding(.horizontal, 8).padding(.vertical, 2)
                                            .background(rec.significance == "HIGH" ? Color.red.opacity(0.15) : Color.orange.opacity(0.15))
                                            .foregroundStyle(rec.significance == "HIGH" ? .red : .orange)
                                            .clipShape(Capsule())
                                    }
                                }

                                if rec.estimatedAnnualSavingCAD > 0 {
                                    Text(String(format: "Est. saving: ~$%.0f CAD/yr (illustrative)", rec.estimatedAnnualSavingCAD))
                                        .font(.subheadline).foregroundStyle(.green)
                                }

                                Text("Why? Wear \(Int(rec.wearScore))/100 on stress \(Int(rec.currentStress))/100 route. Moving to stress \(Int(rec.proposedStress))/100 extends service life.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(4)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    @ViewBuilder
    private func pmRow(_ label: String, _ value: String, color: Color = .primary) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).font(.subheadline)
            Text(value).font(.body.monospacedDigit()).foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func stressChip(_ route: String, stress: Double, label: String) -> some View {
        VStack(spacing: 4) {
            Text(route).font(.subheadline.bold())
            ScoreBar(score: stress).frame(width: 80)
            Text(String(format: "%.0f stress", stress)).font(.caption).foregroundStyle(stress.scoreColor)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
