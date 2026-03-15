import SwiftUI
import Charts

// MARK: - Shared formula card

struct FormulaCard: View {
    let title: String
    let formula: String
    let caption: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(color)
            Text(formula)
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.25)))
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Stats Canada cost data

struct CostDataPoint: Identifiable {
    let id = UUID()
    let year: Int
    let costPerKm: Double
    let isForecast: Bool
}

func buildCostSeries() -> [CostDataPoint] {
    let historical: [(Int, Double)] = [
        (2005,0.32),(2006,0.33),(2007,0.33),(2008,0.35),
        (2009,0.34),(2010,0.35),(2011,0.35),(2012,0.34),(2013,0.37)
    ]
    let n  = Double(historical.count)
    let xs = historical.map { Double($0.0) }
    let ys = historical.map { $0.1 }
    let xBar = xs.reduce(0,+)/n
    let yBar = ys.reduce(0,+)/n
    let numerator   = zip(xs, ys).map { x, y in (x - xBar) * (y - yBar) }.reduce(0.0, +)
    let denominator = xs.map { x in (x - xBar) * (x - xBar) }.reduce(0.0, +)
    let slope       = denominator == 0 ? 0 : numerator / denominator
    let intercept   = yBar - slope * xBar

    var pts = historical.map { CostDataPoint(year:$0.0, costPerKm:$0.1, isForecast:false) }
    for y in 2014...2026 {
        pts.append(CostDataPoint(year:y, costPerKm:max(0, intercept+slope*Double(y)), isForecast:true))
    }
    return pts
}

// MARK: - Section wrapper

struct PresSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title.bold())
            Divider()
            content()
        }
    }
}

// MARK: - Weight slider

struct WeightSlider: View {
    let label: String
    @Binding var value: Double
    let description: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline.bold())
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0...1, step: 0.05)
            Text(description).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Section 4: Weight tuner

private struct WeightTunerSection: View {
    @Binding var w1: Double
    @Binding var w2: Double
    @Binding var w3: Double
    let wSumOK: Bool
    let wSum: Double
    let didRecalculate: Bool
    let liveHighCount: Int
    let liveMedCount: Int
    let onRecalculate: () -> Void

    var body: some View {
        PresSection(title: "Adjust the Model") {
            Text("Change the weights below to see how recommendations shift.")
                .font(.subheadline).foregroundStyle(.secondary)
            WeightSlider(label: "W1 — Distance weight",      value: $w1, description: "Shape distance in km")
            WeightSlider(label: "W2 — Stop count weight",    value: $w2, description: "Unique stops on route")
            WeightSlider(label: "W3 — Passenger load weight", value: $w3, description: "Average PRESTO taps per stop")
            HStack(spacing: 12) {
                if wSumOK {
                    Label(String(format: "✓ Weights balanced (%.2f)", wSum), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.subheadline.bold())
                } else {
                    Label(String(format: "Weights must sum to 1.0 (current: %.2f)", wSum), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.subheadline.bold())
                }
                Spacer()
                Button("Recalculate", action: onRecalculate)
                    .buttonStyle(.borderedProminent).disabled(!wSumOK)
            }
            if didRecalculate {
                HStack(spacing: 20) {
                    Label("\(liveHighCount) HIGH priority swaps", systemImage: "arrow.up.circle.fill").foregroundStyle(.red)
                    Label("\(liveMedCount) MEDIUM priority swaps", systemImage: "arrow.up.circle").foregroundStyle(.orange)
                }
                .font(.title3.bold()).padding()
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

// MARK: - Section 5: Cost projections

private struct CostProjectionsSection: View {
    @Binding var costPerPoint: Double
    @Binding var fleetKmPerYear: Double
    @Binding var maintCostPerKm: Double
    let busCount: Int
    let swapCount: Int
    let totalEstSaving: Double
    let fiveYearSaving: Double

    var body: some View {
        PresSection(title: "Cost Projections") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    Text("$/yr per 10-pt stress reduction").foregroundStyle(.secondary)
                    TextField("", value: $costPerPoint, format: .currency(code: "CAD").precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder).frame(width: 120)
                }
                GridRow {
                    Text("Fleet km/yr (avg per bus)").foregroundStyle(.secondary)
                    TextField("", value: $fleetKmPerYear, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 120)
                }
                GridRow {
                    Text("Maintenance $/km (2026 projected)").foregroundStyle(.secondary)
                    TextField("", value: $maintCostPerKm, format: .currency(code: "CAD").precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder).frame(width: 120)
                }
            }
            .font(.subheadline)

            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 10) {
                        GridRow {
                            Text("Total fleet").foregroundStyle(.secondary)
                            Text("\(busCount) buses").font(.body.bold())
                        }
                        GridRow {
                            Text("Buses recommended for swap").foregroundStyle(.secondary)
                            Text("\(swapCount) buses").font(.body.bold())
                        }
                        GridRow {
                            Text("Estimated annual PM saving").foregroundStyle(.secondary)
                            Text(totalEstSaving, format: .currency(code: "CAD").precision(.fractionLength(0)))
                                .font(.title3.bold()).foregroundStyle(.green)
                        }
                        GridRow {
                            Text("Projected 5-year saving").foregroundStyle(.secondary)
                            Text(fiveYearSaving, format: .currency(code: "CAD").precision(.fractionLength(0)))
                                .font(.title2.bold()).foregroundStyle(.green)
                        }
                    }
                    .padding(.bottom, 8)
                    Text("Assumptions: illustrative estimates only. Validate with DRT finance team.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(6)
            }
        }
    }
}

// MARK: - Section 6A: PM Due chart

private struct PMDueForecastChart: View {
    let dueIn1Week: Int
    let dueIn2Weeks: Int
    var body: some View {
        GroupBox("Preventative Maintenance Due") {
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    BarMark(x: .value("Horizon", "In 1 week"),  y: .value("Buses", dueIn1Week))
                        .foregroundStyle(Color.orange.gradient)
                        .annotation(position: .top) {
                            Text("\(dueIn1Week)").font(.caption).foregroundStyle(.secondary)
                        }
                    BarMark(x: .value("Horizon", "In 2 weeks"), y: .value("Buses", dueIn2Weeks))
                        .foregroundStyle(Color.red.gradient)
                        .annotation(position: .top) {
                            Text("\(dueIn2Weeks)").font(.caption).foregroundStyle(.secondary)
                        }
                }
                .frame(height: 200).chartYAxisLabel("Buses due for PM")
                Text("Based on 250 km/day average daily distance. Actual may vary.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }
}

// MARK: - Section 6B: StatsCan cost chart

private struct StatCanCostChart: View {
    let costSeries: [CostDataPoint]
    let projected2026: Double

    var historicalSeries: [CostDataPoint] { costSeries.filter { !$0.isForecast } }
    var forecastSeries:   [CostDataPoint] { costSeries.filter {  $0.isForecast } }

    var body: some View {
        GroupBox("Urban Bus Maintenance Cost/km — Canada") {
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(historicalSeries) { pt in
                        LineMark(x: .value("Year", pt.year), y: .value("$/km", pt.costPerKm))
                            .foregroundStyle(Color.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.linear)
                        PointMark(x: .value("Year", pt.year), y: .value("$/km", pt.costPerKm))
                            .foregroundStyle(Color.blue)
                    }
                    ForEach(forecastSeries) { pt in
                        LineMark(x: .value("Year", pt.year), y: .value("$/km", pt.costPerKm))
                            .foregroundStyle(Color.orange.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5,3]))
                            .interpolationMethod(.linear)
                    }
                    if let pt2026 = forecastSeries.last(where: { $0.year == 2026 }) {
                        PointMark(x: .value("Year", pt2026.year), y: .value("$/km", pt2026.costPerKm))
                            .foregroundStyle(Color.orange)
                            .annotation(position: .top, alignment: .center) {
                                Text(String(format: "2026: $%.2f/km", pt2026.costPerKm))
                                    .font(.caption.bold()).foregroundStyle(.orange)
                            }
                    }
                }
                .chartYAxisLabel("$/km")
                .chartXAxis {
                    AxisMarks(values: [2005, 2010, 2013, 2020, 2026]) { v in
                        AxisValueLabel { Text(String(v.as(Int.self) ?? 0)) }
                        AxisGridLine()
                    }
                }
                .frame(height: 200)
                HStack(spacing: 16) {
                    Label("Historical 2005–2013", systemImage: "line.diagonal").foregroundStyle(.blue)
                    Label("Forecast 2014–2026",   systemImage: "line.diagonal").foregroundStyle(.orange)
                }
                .font(.caption2)
                Text("Source: Statistics Canada, Table 23-10-0087-01")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }
}

// MARK: - PresentationView

struct PresentationView: View {
    @State private var w1: Double = 0.30
    @State private var w2: Double = 0.40
    @State private var w3: Double = 0.30

    @State private var costPerPoint:   Double = 500
    @State private var fleetKmPerYear: Double = 60_000
    @State private var maintCostPerKm: Double = 0.42

    @State private var buses:    [Bus]    = []
    @State private var routes:   [Route]  = []
    @State private var swapRecs: [SwapRecommendation] = []

    @State private var liveHighCount  = 0
    @State private var liveMedCount   = 0
    @State private var didRecalculate = false

    private let costSeries = buildCostSeries()

    private var wSum: Double  { w1 + w2 + w3 }
    private var wSumOK: Bool  { abs(wSum - 1.0) < 0.001 }
    private var dueIn1Week:  Int { buses.filter { $0.unitstogo <= 1_750 }.count }
    private var dueIn2Weeks: Int { buses.filter { $0.unitstogo <= 3_500 }.count }
    private var projected2026: Double { costSeries.last(where: { $0.year == 2026 })?.costPerKm ?? 0.42 }
    private var totalEstSaving: Double { swapRecs.map(\.estimatedAnnualSavingCAD).reduce(0,+) * (costPerPoint / 500) }
    private var fiveYearSaving: Double { totalEstSaving * 5 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                section1
                section2
                section3
                WeightTunerSection(
                    w1: $w1, w2: $w2, w3: $w3,
                    wSumOK: wSumOK, wSum: wSum,
                    didRecalculate: didRecalculate,
                    liveHighCount: liveHighCount,
                    liveMedCount: liveMedCount,
                    onRecalculate: recalculate
                )
                CostProjectionsSection(
                    costPerPoint: $costPerPoint,
                    fleetKmPerYear: $fleetKmPerYear,
                    maintCostPerKm: $maintCostPerKm,
                    busCount: buses.count,
                    swapCount: swapRecs.count,
                    totalEstSaving: totalEstSaving,
                    fiveYearSaving: fiveYearSaving
                )
                PresSection(title: "Fleet Forecasts") {
                    HStack(alignment: .top, spacing: 24) {
                        PMDueForecastChart(dueIn1Week: dueIn1Week, dueIn2Weeks: dueIn2Weeks)
                        StatCanCostChart(costSeries: costSeries, projected2026: projected2026)
                    }
                }
                Spacer(minLength: 40)
            }
            .padding(28)
        }
        .navigationTitle("Presentation")
        .task {
            buses    = DatabaseManager.shared.fetchBuses()
            routes   = DatabaseManager.shared.fetchRoutes()
            swapRecs = DatabaseManager.shared.fetchSwapRecs()
            if let v = costSeries.last(where: { $0.year == 2026 }) { maintCostPerKm = v.costPerKm }
        }
    }

    // MARK: - Static sections

    private var section1: some View {
        PresSection(title: "The Problem") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Durham Region Transit maintains its fleet using odometer readings and calendar-based triggers — not accounting for the actual stress imposed by individual routes. A bus completing 50 km of express highway service and a bus making 80 urban stops per trip are treated identically by the maintenance schedule.")
                Text("High-stress routes — characterised by frequent stops, high ridership, and longer distances — degrade buses significantly faster than low-stress routes. This creates an unequal fleet lifecycle: some buses arrive at major maintenance events years early while others remain underutilised. The result is higher-than-necessary PM costs and unplanned downtime risk.")
            }
            .font(.system(size: 16)).lineSpacing(5)
        }
    }

    private var section2: some View {
        PresSection(title: "The Solution") {
            VStack(alignment: .leading, spacing: 14) {
                Text("DRT Fleet Equalizer matches bus wear to route stress — rotating buses strategically so that high-wear buses move to lower-stress routes for recovery, while fresher buses take on demanding routes. The goal is to equalise lifecycle across the fleet, delaying major maintenance events and reducing total annual PM spend.")
                Text("Three data sources power the analysis:")
                VStack(alignment: .leading, spacing: 8) {
                    Label("DRT Preventative Maintenance Records — bus wear state (odometer, days overdue, units late)", systemImage: "wrench.and.screwdriver.fill")
                    Label("PRESTO Full-Year Ridership (2025) — stop-level passenger load as a stress proxy", systemImage: "creditcard.fill")
                    Label("GTFS Static Feed + Rate My Ride — route geometry, stop topology, and bus-to-route history (proxy via rider feedback)", systemImage: "map.fill")
                }
                .font(.system(size: 15)).foregroundStyle(.secondary)
            }
            .font(.system(size: 16)).lineSpacing(5)
        }
    }

    private var section3: some View {
        PresSection(title: "How We Score It") {
            HStack(alignment: .top, spacing: 16) {
                FormulaCard(
                    title: "Wear Score",
                    formula: "WearScore =\n  (OdometerKm × 0.4)\n+ (KmLate    × 0.3)\n+ (DaysLate  × 0.3)\n\nNormalised 0–100",
                    caption: "Measures how hard a bus has been driven relative to its PM schedule. Higher = more worn.",
                    color: .red
                )
                FormulaCard(
                    title: "Route Stress Score",
                    formula: "RouteStress =\n  norm(ShapeDistKm)  × W1\n+ norm(StopCount)    × W2\n+ norm(AvgTaps/Stop) × W3\n\nNormalised 0–100",
                    caption: "Measures how physically demanding a route is. Higher = more stressful on a bus.",
                    color: .orange
                )
                FormulaCard(
                    title: "Swap Priority Score",
                    formula: "SwapScore =\n  WearScore\n+ CurrentRouteStress\n− ProposedRouteStress",
                    caption: "Prioritises which bus rotations to action first. Higher = more urgent.",
                    color: .blue
                )
            }
        }
    }

    // MARK: - Recalculate

    private func recalculate() {
        guard wSumOK else { return }

        func normVals(_ vals: [Double]) -> [Double] {
            let mn = vals.min() ?? 0, mx = vals.max() ?? 0
            guard mx > mn else { return vals.map { _ in 50 } }
            return vals.map { ($0 - mn) / (mx - mn) * 100 }
        }

        let nDist  = normVals(routes.map { $0.shapeDistanceKm })
        let nStops = normVals(routes.map { Double($0.stopCount) })
        let nTaps  = normVals(routes.map { $0.avgTapsPerStop })
        let rawStress = zip(zip(nDist, nStops), nTaps).map { pair, tap in pair.0*w1 + pair.1*w2 + tap*w3 }
        let normStress = normVals(rawStress)

        var stressMap: [String: Double] = [:]
        for (i, route) in routes.enumerated() { stressMap[route.routeShortName] = normStress[i] }

        let rawWear  = buses.map { $0.lastreading * 0.4 + $0.unitslate * 0.3 + $0.dayslate * 0.3 }
        let normWear = normVals(rawWear)
        var wearMap: [String: Double] = [:]
        for (i, bus) in buses.enumerated() { wearMap[bus.alias] = normWear[i] }

        var high = 0, med = 0
        for rec in swapRecs {
            let ws = wearMap[rec.busAlias] ?? rec.wearScore
            let cs = stressMap[rec.currentRoute] ?? rec.currentStress
            let ps = stressMap[rec.proposedRoute] ?? rec.proposedStress
            guard ws + cs - ps > 0 else { continue }
            if rec.wearDelta >= 25 { high += 1 } else if rec.wearDelta >= 15 { med += 1 }
        }

        liveHighCount  = high
        liveMedCount   = med
        didRecalculate = true
    }
}
