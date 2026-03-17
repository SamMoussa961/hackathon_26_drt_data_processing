# Lifecycle Cost-Balanced Bus Operations  (LCBO)

A data pipeline and macOS dashboard that recommends bus rotations to equalize fleet lifecycle and reduce maintenance costs for Durham Region Transit.

---

## The Problem

Durham Region Transit maintains its buses on fixed schedules — a bus gets serviced every X kilometres or every Y days, regardless of what it did in between. That sounds fair, but it isn't. A bus assigned to a short, flat urban route and a bus grinding through long rural corridors with heavy passenger loads are not experiencing the same wear. The schedule treats them identically.

The result is an uneven fleet. Some buses accumulate wear far faster than the maintenance calendar accounts for, leading to higher repair costs and earlier retirement. Others run light routes, reach retirement age, and leave service with usable mechanical life still on the table. No tool existed inside DRT's current workflow to see this pattern or act on it.

---

## The Solution

The system assigns three scores to give fleet managers a clear, actionable picture.

### WearScore (per bus, 0–100)

```
WearScore = W1 × (open_pm_count / max_pm_count)
          + W2 × (overdue_pm_count / max_pm_count)
          + W3 × (critical_pm_count / max_pm_count)
```

| Variable | Meaning |
|---|---|
| `open_pm_count` | Number of open preventative maintenance work orders for this bus |
| `overdue_pm_count` | Number of those work orders that are past due |
| `critical_pm_count` | Number flagged as critical priority |
| `W1, W2, W3` | Adjustable weights (default: 0.4, 0.3, 0.3) |

A higher WearScore means the bus is carrying more maintenance burden relative to the rest of the fleet.

### RouteStress (per route, 0–100)

```
RouteStress = W1 × (stop_count / max_stop_count)
            + W2 × (passenger_taps / max_passenger_taps)
            + W3 × (shape_distance_km / max_shape_distance_km)
```

| Variable | Meaning |
|---|---|
| `stop_count` | Number of stops on the route — more stops means more acceleration/braking cycles |
| `passenger_taps` | Annual PRESTO fare taps — a proxy for passenger load |
| `shape_distance_km` | Total route distance calculated from GTFS geometry using haversine |
| `W1, W2, W3` | Adjustable weights (default: 0.3, 0.4, 0.3) |

A higher RouteStress means the route imposes more mechanical demand on whatever bus runs it.

### SwapScore (per recommendation)

```
SwapScore = WearScore(bus_from) - WearScore(bus_to)
```

| Variable | Meaning |
|---|---|
| `WearScore(bus_from)` | Wear score of the high-wear bus being moved off the stressful route |
| `WearScore(bus_to)` | Wear score of the lower-wear bus being moved onto it |

A higher SwapScore means the rotation delivers a larger equalisation benefit. Swaps are only generated when this delta meets a minimum threshold and all coverage constraints are satisfied.

---

## Data Sources

| Source | What it contains | How it's used |
|---|---|---|
| DRT Preventative Maintenance HotList | 206 open work orders, February 2026 snapshot | Calculates WearScore per bus using open, overdue, and critical PM counts |
| PRESTO fare tap data | 500,000+ transactions across 12 monthly files, full year 2025 | Aggregates passenger load per stop per route for RouteStress |
| GTFS Static Feed (Durham Region Transit) | Stops, routes, trips, shapes, stop_times | Provides stop counts and route geometry for distance and density scoring |
| Rate My Ride rider feedback | Vehicle label and route short name per submission | Acts as a proxy to link bus numbers to the routes they operate — no direct assignment log exists in the static data |
| Statistics Canada Table 23-10-0087-01 | Urban transit maintenance cost per kilometre, 2005–2013 | Provides a cost-per-km baseline extrapolated to 2026 via linear regression for the cost projection view |

---

## Repository Structure

```
/
├── LifecycleCostBalancedBusOperations/   ← Xcode project (SwiftUI macOS app)
│   ├── App/                              ← App entry point and environment setup
│   ├── Database/                         ← SQLite connection and query layer
│   ├── Models/                           ← Swift data models matching DB schema
│   └── Views/                            ← Fleet Health, Route Stress, Swap Engine, Presentation
├── dataset_processing/                   ← Python data pipeline
│   ├── build_db.py                       ← Single-file pipeline: ingests all sources, writes drt_fleet.db
│   └── pyproject.toml                    ← uv project and dependency configuration
├── DurhamRegionTransitData/              ← Raw data directory (gitignored — not committed)
├── GTFS_Durham_TXT/                      ← GTFS static files (gitignored — not committed)
└── README.md                             ← This file
```

---

## How to Run

### Pipeline

1. Clone the repository:
   ```bash
   git clone <repo-url>
   cd hackathon_26_drt_data_processing
   ```

2. Install dependencies using uv:
   ```bash
   uv sync
   ```

3. Run the pipeline:
   ```bash
   uv run python dataset_processing/build_db.py
   ```

   The pipeline prints a summary to the console and writes `drt_fleet.db` into `dataset_processing/`.

> **Note:** Data files are not included in this repository. Contact DRT or Durham College hackathon organisers for access to the PM HotList, PRESTO exports, and Rate My Ride data. Place data folders at the repo root matching the paths expected in `build_db.py`.

---

### macOS App

1. Open `LifecycleCostBalancedBusOperations/LifecycleCostBalancedBusOperations.xcodeproj` in Xcode.

2. Add `drt_fleet.db` to the app target:
   - Drag `drt_fleet.db` from `dataset_processing/` into the Xcode project navigator.
   - In the dialog, check **Copy items if needed** and ensure **LifecycleCostBalancedBusOperations** is checked under **Add to targets**.

3. Select the **My Mac** scheme from the scheme selector.

4. Press **⌘R** to build and run.

---

## Formulas

```
WearScore = 0.4 × (open_pm / max_open_pm)
          + 0.3 × (overdue_pm / max_overdue_pm)
          + 0.3 × (critical_pm / max_critical_pm)
```
Normalises each bus's maintenance burden to a 0–100 scale so buses with very different raw counts can be compared directly.

```
RouteStress = 0.3 × (stops / max_stops)
            + 0.4 × (taps / max_taps)
            + 0.3 × (distance_km / max_distance_km)
```
Combines three independent sources of route difficulty — structural, demand, and geographic — into a single comparable score.

```
SwapScore = WearScore(high_wear_bus) - WearScore(replacement_bus)
```
Quantifies the equalisation benefit of a specific rotation; only swaps with a delta ≥ 10 are surfaced as recommendations.

---

## Assumptions and Limitations

- **Bus-to-route assignment is a proxy.** The link between a bus number and the route it runs is derived from Rate My Ride rider feedback — not from DRT's CAD vehicle assignment system. Direct assignment logs would significantly improve accuracy.
- **Cost estimates are illustrative.** The figure of approximately $500/year saved per 10-point stress reduction is a placeholder based on extrapolated StatsCan data, not an audited operational number.
- **Daily distance is assumed at 250 km/day** for the PM forecast chart. Actual mileage per vehicle would sharpen this projection.
- **StatsCan data ends at 2013.** Values from 2014 to 2026 are produced by linear regression extrapolation and carry the uncertainty that implies.
- **Scoring weights are adjustable by design.** Default weights (WearScore: 0.4 / 0.3 / 0.3; RouteStress: 0.3 / 0.4 / 0.3) are reasonable starting points, not validated parameters. The Presentation view exposes sliders precisely because the right weights are a conversation DRT should have with this data in front of them.

---

## Judging Criteria Alignment

- **Technology:** Combines a real multi-source data pipeline (GTFS, PRESTO, PM records, StatsCan) with a native macOS app — no mock data, no placeholder APIs, no scaffolded demo.
- **Design:** The four-view dashboard is structured for an operations manager's workflow — triage worn buses, understand stressful routes, act on swap recommendations, demonstrate findings to stakeholders.
- **Completion:** The pipeline runs end-to-end and produces a populated database. The app reads it, renders all four views, and the Presentation mode is fully interactive with live recalculation.
- **Learning:** The project surfaced a real insight about scheduled maintenance vs. route-adjusted wear that DRT's current tooling does not surface — and built the tool that would.

---

**Durham College Hackathon 2026 — Durham Region Transit Challenge**

---

*“I’ve used Claude Code to support code generation, idea organization, grammar refinement, and clarity improvement only. All final content and analysis were created by me."*