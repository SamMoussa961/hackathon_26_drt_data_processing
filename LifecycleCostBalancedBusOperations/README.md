# Lifecycle Cost-Balanced Bus Operations  (LCBO) — macOS App

A native macOS SwiftUI dashboard that reads the fleet database produced by the Python pipeline and presents operational views for triaging bus wear, understanding route stress, and acting on swap recommendations.

---

## Requirements

| Requirement | Minimum version |
|---|---|
| macOS | 14.0 (Sonoma) |
| Xcode | 15.0 |
| Swift | 5.9 |
| Database | `drt_fleet.db` produced by `dataset_processing/build_db.py` |

---

## Setup

### Add the database to the Xcode target

1. Run the pipeline to produce `drt_fleet.db` (it lands in `dataset_processing/`).
2. In Xcode, open the project navigator (**⌘1**).
3. Drag `drt_fleet.db` into the navigator.
4. In the sheet that appears:
   - Check **Copy items if needed**
   - Ensure **LifecycleCostBalancedBusOperations** is checked under **Add to targets**
5. Click **Finish**.

The app locates the database using `Bundle.main.url(forResource:withExtension:)` at launch.

### Add SQLite.swift via Swift Package Manager

1. In Xcode, go to **File → Add Package Dependencies…**
2. Enter the package URL: `https://github.com/stephencelis/SQLite.swift`
3. Select **Up to Next Major Version** from the current release.
4. Click **Add Package** and add `SQLite` to the **LifecycleCostBalancedBusOperations** target.

---

## Views

### Fleet Health

Displays all buses as a sortable `Table` with columns for bus alias, WearScore, current route, and open PM count. Rows are colour-coded by wear tier: green for low wear (0–39), amber for moderate (40–69), and red for high (70–100). Clicking any row opens a detail sheet showing the full breakdown of wear component values for that bus, along with its score.

### Route Stress

Displays all routes as a sortable `Table` with columns for route short name, RouteStress score, stop count, shape distance, average taps per stop, and the number of buses currently assigned. Rows are colour-coded by stress tier using the same green/amber/red scale. This view is the starting point for understanding which routes should receive lower-wear buses.

### Swap Engine

Presents swap recommendations grouped by the current route of the high-wear bus being rotated. Each group shows a card for every recommendation on that route, including the outgoing bus alias, the incoming replacement bus alias, the wear delta, estimated annual saving, and a significance badge (HIGH or MEDIUM). A filter toolbar allows the user to show only HIGH significance swaps or to filter by route. A disclaimer footer reminds the user that recommendations are based on Rate My Ride proxy data and should be validated against actual vehicle assignment records before action.

### Presentation

An interactive demo mode designed for showing findings to stakeholders. It walks through a structured narrative: the problem statement, the solution approach, the three formula cards with variable explanations, and live interactive weight sliders for both WearScore and RouteStress. Adjusting any slider triggers an in-memory rescore of all buses and routes without rerunning the pipeline — the raw component values are stored in the database for exactly this purpose. The view also includes cost projection inputs (cost per km, average daily distance), a PM forecast bar chart built with Swift Charts, and a maintenance cost trend line chart overlaying the historical Statistics Canada data with the 2026 linear extrapolation highlighted.

---

## Database schema

```sql
CREATE TABLE buses (
    alias               TEXT PRIMARY KEY,
    lastreading         REAL,
    unitstogo           REAL,
    unitslate           REAL,
    dayslate            REAL,
    wear_score          REAL,
    current_route       TEXT
);

CREATE TABLE routes (
    route_id            TEXT PRIMARY KEY,
    route_short_name    TEXT,
    stop_count          INTEGER,
    shape_distance_km   REAL,
    avg_taps_per_stop   REAL,
    stress_score        REAL
);

CREATE TABLE bus_route_hist (
    vehicle_label       TEXT,
    route_short_name    TEXT,
    trip_count          INTEGER
);

CREATE TABLE swap_recs (
    bus_alias                   TEXT,
    current_route               TEXT,
    proposed_route              TEXT,
    wear_score                  REAL,
    current_stress              REAL,
    proposed_stress             REAL,
    swap_score                  REAL,
    estimated_annual_saving_cad REAL,
    wear_delta                  REAL,
    significance                TEXT
);
```

---

## Key design decisions

- **`NavigationSplitView` over `TabView`** — macOS dashboard ergonomics favour a persistent sidebar with a detail area rather than a tab strip. The split view keeps all four sections visible and navigable without covering the active view.
- **All data is local SQLite — no network calls at runtime.** The app has no dependencies on external APIs or live feeds. Once the database is bundled, it runs entirely offline. This was a deliberate choice for reliability in a demo context.
- **Swift Charts for all visualisations.** No third-party chart libraries are used. The PM forecast and Statistics Canada cost trend charts are built entirely with the system framework, keeping the dependency surface minimal.
- **Raw score components are stored in the database to enable client-side rescoring.** The pipeline writes `lastreading`, `unitslate`, `dayslate`, `stop_count`, `shape_distance_km`, and `avg_taps_per_stop` alongside the pre-computed scores. This means the Presentation view's weight sliders can recalculate every score in memory instantly — the user sees live results without waiting for a pipeline re-run.

---

**Durham College Hackathon 2026 — Durham Region Transit Challenge**

---

*“I’ve used Claude Code to support code generation, idea organization, grammar refinement, and clarity improvement only. All final content and analysis were created by me."*