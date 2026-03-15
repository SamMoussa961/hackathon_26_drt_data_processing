import SwiftUI

struct RouteStressView: View {
    @State private var routes:      [Route] = []
    @State private var busCounts:   [String: Int] = [:]
    @State private var selected:    Route.ID?
    @State private var detailRoute: Route?

    var body: some View {
        Table(routes, selection: $selected) {
            TableColumn("Route") { route in
                Text("Route \(route.routeShortName)").font(.body.bold())
            }
            .width(min: 80, ideal: 90)

            TableColumn("Stress Score") { route in
                HStack(spacing: 8) {
                    ScoreBar(score: route.stressScore).frame(width: 80)
                    Text(String(format: "%.0f", route.stressScore))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(route.stressScore.scoreColor)
                        .frame(width: 28, alignment: .trailing)
                }
            }
            .width(min: 120, ideal: 130)

            TableColumn("Stops") { route in
                Text("\(route.stopCount)").font(.subheadline.monospacedDigit())
            }
            .width(min: 60, ideal: 70)

            TableColumn("Distance km") { route in
                Text(String(format: "%.1f", route.shapeDistanceKm))
                    .font(.subheadline.monospacedDigit())
            }
            .width(min: 90, ideal: 100)

            TableColumn("Avg Taps/Stop") { route in
                Text(String(format: "%.1f", route.avgTapsPerStop))
                    .font(.subheadline.monospacedDigit())
            }
            .width(min: 100, ideal: 110)

            TableColumn("Buses") { route in
                let count = busCounts[route.routeShortName] ?? 0
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(count == 0 ? .orange : .primary)
            }
            .width(min: 60, ideal: 70)
        }
        .navigationTitle("Route Stress")
        .navigationSubtitle("\(routes.count) routes")
        .onChange(of: selected) { _, newID in
            detailRoute = routes.first { $0.id == newID }
        }
        .sheet(item: $detailRoute) { route in
            RouteDetailSheet(route: route, busCount: busCounts[route.routeShortName] ?? 0)
        }
        .task {
            routes    = DatabaseManager.shared.fetchRoutes()
            busCounts = DatabaseManager.shared.fetchRouteBusCounts()
        }
    }
}

// MARK: - Route detail sheet

private struct RouteDetailSheet: View {
    let route: Route
    let busCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Route \(route.routeShortName)").font(.largeTitle.bold())
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(format: "Stress Score: %.1f / 100", route.stressScore))
                                .font(.title2.bold()).foregroundStyle(route.stressScore.scoreColor)
                            ScoreBar(score: route.stressScore).frame(width: 200)
                        }
                        Spacer()
                    }

                    GroupBox("Stress Components") {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                            GridRow {
                                Text("Stop Count (W=0.4)").foregroundStyle(.secondary).font(.subheadline)
                                Text("\(route.stopCount) unique stops").font(.body.monospacedDigit())
                            }
                            GridRow {
                                Text("Shape Distance (W=0.3)").foregroundStyle(.secondary).font(.subheadline)
                                Text(String(format: "%.2f km", route.shapeDistanceKm)).font(.body.monospacedDigit())
                            }
                            GridRow {
                                Text("Avg Taps/Stop (W=0.3)").foregroundStyle(.secondary).font(.subheadline)
                                Text(String(format: "%.1f taps", route.avgTapsPerStop)).font(.body.monospacedDigit())
                            }
                            GridRow {
                                Text("Buses Assigned").foregroundStyle(.secondary).font(.subheadline)
                                Text("\(busCount) buses").font(.body.monospacedDigit())
                            }
                        }
                        .padding(4)
                    }

                    GroupBox("Formula") {
                        Text("RouteStress = norm(distance)×0.3 + norm(stops)×0.4 + norm(taps/stop)×0.3\nNormalised 0–100 across all DRT routes.")
                            .font(.caption.monospaced()).foregroundStyle(.secondary).padding(4)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 460, minHeight: 360)
    }
}
