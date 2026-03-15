import SwiftUI

struct SwapEngineView: View {
    @State private var swapRecs:       [SwapRecommendation] = []
    @State private var busCounts:      [String: Int] = [:]
    @State private var routeAvgStress: [String: Double] = [:]
    @State private var showHighOnly    = false
    @State private var searchText      = ""

    private var filtered: [SwapRecommendation] {
        var list = swapRecs
        if showHighOnly { list = list.filter { $0.significance == "HIGH" } }
        if !searchText.isEmpty {
            list = list.filter {
                $0.busAlias.localizedCaseInsensitiveContains(searchText) ||
                $0.currentRoute.localizedCaseInsensitiveContains(searchText) ||
                $0.proposedRoute.localizedCaseInsensitiveContains(searchText)
            }
        }
        return list
    }

    private var groups: [(route: String, recs: [SwapRecommendation])] {
        let grouped = Dictionary(grouping: filtered, by: { $0.currentRoute })
        return grouped
            .map { (route: $0.key, recs: $0.value) }
            .sorted { (routeAvgStress[$0.route] ?? 0) > (routeAvgStress[$1.route] ?? 0) }
    }

    private let cad: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencyCode = "CAD"; f.maximumFractionDigits = 0; return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 16) {
                Toggle("HIGH only", isOn: $showHighOnly).toggleStyle(.checkbox)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search bus, route…", text: $searchText).textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 240)
                Spacer()
                Text("\(filtered.count) recommendations").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if groups.isEmpty {
                ContentUnavailableView("No Swaps Match", systemImage: "arrow.2.squarepath",
                    description: Text("Try removing filters or broadening your search."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20, pinnedViews: .sectionHeaders) {
                        ForEach(groups, id: \.route) { group in
                            Section {
                                ForEach(group.recs) { rec in
                                    SwapCard(rec: rec, cadFormatter: cad).padding(.horizontal, 16)
                                }
                            } header: {
                                RouteGroupHeader(
                                    route: group.route,
                                    busCount: busCounts[group.route] ?? 0,
                                    avgStress: routeAvgStress[group.route] ?? 0,
                                    recCount: group.recs.count
                                )
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
            }

            Divider()
            Text("Bus-to-route assignment derived from Rate My Ride rider feedback (proxy data). Recommendations require operational validation before implementation.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(10)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle("Swap Engine")
        .navigationSubtitle("\(swapRecs.count) recommendations")
        .task {
            swapRecs  = DatabaseManager.shared.fetchSwapRecs()
            busCounts = DatabaseManager.shared.fetchRouteBusCounts()
            var stressMap: [String: [Double]] = [:]
            for rec in swapRecs { stressMap[rec.currentRoute, default: []].append(rec.currentStress) }
            routeAvgStress = stressMap.mapValues { $0.reduce(0,+) / Double($0.count) }
        }
    }
}

// MARK: - Route group header

private struct RouteGroupHeader: View {
    let route: String; let busCount: Int; let avgStress: Double; let recCount: Int
    var body: some View {
        HStack(spacing: 12) {
            Text("Route \(route)").font(.title3.bold())
            Spacer()
            Label("\(busCount) buses", systemImage: "bus.fill").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ScoreBar(score: avgStress).frame(width: 60)
                Text(String(format: "%.0f stress", avgStress))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(avgStress.scoreColor)
            }
            Text("\(recCount) rec\(recCount == 1 ? "" : "s")")
                .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.blue.opacity(0.12)).foregroundStyle(.blue).clipShape(Capsule())
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Swap card

private struct SwapCard: View {
    let rec: SwapRecommendation
    let cadFormatter: NumberFormatter
    @State private var expanded = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Bus \(rec.busAlias)").font(.headline)
                            significanceBadge
                        }
                        Text("Route assignment based on rider-feedback proxy data")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if rec.estimatedAnnualSavingCAD > 0 {
                        Text("~\(cadFormatter.string(from: rec.estimatedAnnualSavingCAD as NSNumber) ?? "—")/yr (est.)")
                            .font(.subheadline.bold()).foregroundStyle(.green)
                    }
                }

                HStack(spacing: 20) {
                    routeBlock(rec.currentRoute,  stress: rec.currentStress,  label: "Current")
                    Image(systemName: "arrow.right.circle.fill").font(.title2).foregroundStyle(.blue)
                    routeBlock(rec.proposedRoute, stress: rec.proposedStress, label: "Proposed")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Wear Δ").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "+%.1f", rec.wearDelta))
                            .font(.title3.bold().monospacedDigit()).foregroundStyle(.green)
                        Text("Swap \(String(format: "%.0f", rec.swapScore))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Bus Wear").font(.caption).foregroundStyle(.secondary).frame(width: 65, alignment: .leading)
                    ScoreBar(score: rec.wearScore)
                    Text(String(format: "%.0f", rec.wearScore))
                        .font(.caption.monospacedDigit()).foregroundStyle(rec.wearScore.scoreColor)
                        .frame(width: 28, alignment: .trailing)
                }

                DisclosureGroup(isExpanded: $expanded) {
                    Text("Bus \(rec.busAlias) scores \(Int(rec.wearScore))/100 for wear on Route \(rec.currentRoute) (stress \(Int(rec.currentStress))/100). Moving to Route \(rec.proposedRoute) (stress \(Int(rec.proposedStress))/100) reduces cumulative mechanical stress by \(Int(rec.currentStress - rec.proposedStress)) points, extending brake and engine life. Wear Δ of \(String(format: "%.1f", rec.wearDelta)) pts confirms a \(rec.significance) significance swap.\n\nSwapScore = WearScore + CurrentStress − ProposedStress = \(String(format: "%.1f", rec.swapScore))")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                } label: {
                    Text("Why this swap?").font(.caption).foregroundStyle(.blue)
                }
            }
            .padding(4)
        }
    }

    private var significanceBadge: some View {
        Text(rec.significance)
            .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 2)
            .background(rec.significance == "HIGH" ? Color.red.opacity(0.15) : Color.orange.opacity(0.15))
            .foregroundStyle(rec.significance == "HIGH" ? .red : .orange)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func routeBlock(_ route: String, stress: Double, label: String) -> some View {
        VStack(spacing: 4) {
            Text("Route \(route)").font(.subheadline.bold())
            ScoreBar(score: stress).frame(width: 90)
            Text(String(format: "%.0f stress", stress)).font(.caption).foregroundStyle(stress.scoreColor)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
