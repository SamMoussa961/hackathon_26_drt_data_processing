# Lifecycle Cost-Balanced Bus Operations  (LCBO) — Data Pipeline

`build_db.py` is the data pipeline for the **Lifecycle Cost-Balanced Bus Operations  (LCBO)** hackathon project. It ingests five heterogeneous data sources, computes fleet wear and route stress scores, applies a constraint-aware swap recommendation algorithm, and writes all results to a local SQLite database consumed by the macOS dashboard.

---

## Problem Statement

Durham Region Transit maintains its fleet on odometer and calendar triggers — not on actual route stress. High-stress routes (frequent stops, high ridership, long distances) degrade buses faster than low-stress routes, creating an unequal fleet lifecycle: some buses arrive at major PM events years early while others are underutilised. The result is higher-than-necessary maintenance costs and unplanned downtime risk.

**This pipeline quantifies that inequality and recommends targeted bus rotations to equalise it.**

---

## Data Sources

| File | Key fields | Role |
|---|---|---|
| `20260212 Preventative Maintenance Open Activities.csv` | `alias`, `lastreading`, `unitslate`, `dayslate` | Bus wear state (PM HotList) |
| `DRTON_rate_my_ride.csv` | `vehicle_label`, `route_short_name`, `trip_id` | Only source linking buses to routes historically |
| `GTFS_Durham_TXT/` | routes, trips, stop_times, shapes, stops | Route geometry and stop topology |
| `DurhamRegionTransitData/PRESTO/` | `trxlocationid`, tap count | Full-year 2025 passenger load (12 monthly CSVs) |

### Key join chain

```
PM HotList   alias
                └── Rate My Ride   vehicle_label  ──→  route_short_name
                                                            └── GTFS routes.route_id
PRESTO   trxlocationid  (float-serialised stop code)
             └── GTFS stops.stop_code → stop_id
                     └── GTFS stop_times.stop_id → trip_id
                                 └── GTFS trips.trip_id → route_id
```

> PRESTO has **no vehicle column**. Passenger load is aggregated at the stop level and averaged per route. Rate My Ride is the **only** source that historically links a specific bus to a specific route — it is used as a proxy for current assignment.

---

## Pipeline Steps

### Step 1 — Rate My Ride
Load `DRTON_rate_my_ride.csv`. Normalise `vehicle_label` from float string (`"8616.0"`) to integer string (`"8616"`) to enable joins with the PM HotList.

### Step 2 — GTFS
Load stops, routes, trips, stop_times (trip_id + stop_id only), and shapes from `GTFS_Durham_TXT/` using `pd.read_csv`. No external GTFS library required.

### Step 3a — Stop count per route
Join `stop_times → trips` on `trip_id` to assign each stop occurrence to a `route_id`. Count **unique** stops per route (a stop appearing on multiple trips is counted once).

### Step 3b — Shape distance per route
Sort shape points by `(shape_id, shape_pt_sequence)`. Sum haversine distances between consecutive points per `shape_id`. Join `trips → shapes` to get distance per route; average across shape variants (express, inbound, outbound).

### Step 3c — Avg taps per stop per route (full-year PRESTO)
Concatenate all 12 monthly PRESTO CSVs (~6.7 M rows total). Normalise `trxlocationid` from float to integer string. Bridge through `stops.stop_code` → `stop_id` → `stop_times` → `trips.route_id`. Compute mean tap count per stop per route.

### Step 3e — RouteStress
Merge stop count, shape distance, and avg taps into a single per-route DataFrame. Compute weighted normalised stress score.

### Step 4 — WearScore
Load PM HotList. Drop non-numeric `alias` rows (e.g. "String" header bleed). Aggregate multiple PM work orders per bus to worst-case (`max`) values. Compute raw wear and normalise.

### Step 5 — Bus↔Route history
Group Rate My Ride by `(vehicle_label, route_short_name)`, count trips. The most-frequent route per bus becomes its proxy current assignment.

### Step 6 — Swap recommendations *(see algorithm below)*

### Step 7 — Write SQLite
Write four tables to `drt_fleet.db`: `buses`, `routes`, `bus_route_hist`, `swap_recs`.

### Step 8 — Summary
Print fleet size, route count, per-route table, and top-5 swap recommendations to console.

---

## Algorithms & Math

### WearScore (per bus)

Multiple PM rows per bus are collapsed to `max()` before scoring to capture the worst outstanding service need.

```
raw_wear  = (lastreading × 0.4) + (unitslate × 0.3) + (dayslate × 0.3)
WearScore = min_max_normalise(raw_wear, 0–100)
```

| Field | Meaning | Weight |
|---|---|---|
| `lastreading` | Odometer at last PM (km) — proxy for total lifetime distance | 0.40 |
| `unitslate` | km/hours overdue for next PM service | 0.30 |
| `dayslate` | Calendar days overdue for PM service | 0.30 |

**Higher WearScore = more worn.** 100 = worst in fleet; 0 = best.

---

### RouteStress (per route)

Each component is independently normalised 0–100 before weighting, then the weighted sum is re-normalised:

```
raw_stress  = norm(shape_distance_km) × 0.30
            + norm(stop_count)         × 0.40
            + norm(avg_taps_per_stop)  × 0.30
RouteStress = min_max_normalise(raw_stress, 0–100)
```

| Component | Source | Weight | Rationale |
|---|---|---|---|
| `shape_distance_km` | GTFS shapes.txt, haversine sum | 0.30 | Longer routes = more engine and brake wear |
| `stop_count` | Unique stops per route (stop_times + trips) | 0.40 | More stops = more braking events, door cycles, idle time |
| `avg_taps_per_stop` | PRESTO full-year taps ÷ stops on route | 0.30 | Higher ridership = more boarding load, dwell-time variance |

Weights W1/W2/W3 are configurable in the UI (Presentation → Adjust the Model). They must sum to 1.0.

**Haversine formula** (shape distance between consecutive GPS points):

```
a = sin²(Δlat/2) + cos(lat₁)·cos(lat₂)·sin²(Δlon/2)
d = 2R · atan2(√a, √(1−a))    R = 6371 km
```

Routes with multiple shape variants use the **mean** distance across variants.

---

### Normalisation

All normalisation is min-max across the full fleet/route set:

```
normalised = (x − min) / (max − min) × 100
```

When `min == max` (perfectly flat distribution), all values are set to `50.0` to avoid division by zero.

---

### Swap Recommendation Algorithm

The improved algorithm enforces real-world operational constraints before generating any recommendation.

#### Constraints (applied to every candidate swap)

| Rule | Detail |
|---|---|
| **No empty routes** | A route can only lose a bus if it retains ≥ 1 bus after the swap. |
| **Night routes included** | Routes starting with `"N"` follow the same constraint — never emptied. |
| **Ghost routes excluded** | Routes with `stress_score == 0` **and** no buses currently assigned are excluded as both swap sources and targets. |
| **Max recs per route** | Recommendations for a given route ≤ current bus count on that route. |
| **Each bus appears once** | A bus alias appears in `swap_recs` at most once across all recommendations. |
| **Minimum wear delta** | A swap is only recorded if `wear_delta ≥ 15` points (not significant = no row written). |

#### HIGH-stress route swaps (route stress > 60)

For each bus on a high-stress route that is **not** the lowest-wear bus there (i.e., it is a worn bus):
1. Search the low-stress bus pool (all available buses from routes with stress < 40, sorted by wear ascending).
2. The pool candidate's route must have ≥ 2 buses (so removing one doesn't empty it).
3. Compute `wear_delta = worn_bus.wear_score − candidate.wear_score`.
4. If `wear_delta ≥ 15`: record the swap. Mark both buses as used.

The worn bus is recommended to move **to** the low-stress route (relief). The fresh bus would come **from** the low-stress route to the high-stress route.

#### LOW-stress route swaps (route stress < 40)

For the most-worn available bus on each low-stress route:
1. Scan high-stress routes (stress > 60) in ascending stress order (gentlest first).
2. On the target route, confirm the bus would become the **lowest-wear** bus (its wear score < every current bus on that route).
3. Identify the least-worn current bus on the target route as the bus coming back.
4. Compute `wear_delta = target_least_worn.wear_score − most_worn.wear_score`.
5. If `wear_delta ≥ 15`: record the swap. Mark both buses as used.

#### SwapScore and significance

```
SwapScore = WearScore + CurrentRouteStress − ProposedRouteStress
```

| `wear_delta` | `significance` |
|---|---|
| ≥ 25 pts | `HIGH` |
| 15–24 pts | `MEDIUM` |
| < 15 pts | Not recorded |

#### Estimated annual saving

```
estimated_annual_saving_cad = max(0, (current_stress − proposed_stress) / 10 × $500)
```

Applied only to **HIGH-stress → LOW-stress** moves (stress reduction cases). Set to `$0` for LOW → HIGH moves (no stress reduction). The `$500/10-point` figure is a **placeholder** — clearly labelled as illustrative in all outputs.

---

## Output: `drt_fleet.db` (SQLite)

### `buses`
| Column | Type | Description |
|---|---|---|
| `alias` | TEXT | Bus number |
| `lastreading` | REAL | Odometer at last PM (km) |
| `unitstogo` | REAL | km remaining until next PM trigger |
| `unitslate` | REAL | km overdue |
| `dayslate` | REAL | Calendar days overdue |
| `wear_score` | REAL | 0–100 |
| `current_route` | TEXT | Most-frequent route from Rate My Ride (proxy) |

### `routes`
| Column | Type | Description |
|---|---|---|
| `route_id` | TEXT | GTFS internal route ID |
| `route_short_name` | TEXT | Public route number (e.g. "905") |
| `stop_count` | INTEGER | Unique stops served |
| `shape_distance_km` | REAL | Mean route length in km |
| `avg_taps_per_stop` | REAL | Mean PRESTO taps per stop (full year 2025) |
| `stress_score` | REAL | 0–100 |

### `bus_route_hist`
| Column | Type | Description |
|---|---|---|
| `vehicle_label` | TEXT | Bus number |
| `route_short_name` | TEXT | Route |
| `trip_count` | INTEGER | Observed trips on this route (Rate My Ride) |

### `swap_recs`
| Column | Type | Description |
|---|---|---|
| `bus_alias` | TEXT | Bus number |
| `current_route` | TEXT | Current most-frequent route |
| `proposed_route` | TEXT | Recommended new route |
| `wear_score` | REAL | Bus wear 0–100 |
| `current_stress` | REAL | Current route stress 0–100 |
| `proposed_stress` | REAL | Proposed route stress 0–100 |
| `swap_score` | REAL | Priority score (higher = act first) |
| `estimated_annual_saving_cad` | REAL | Illustrative saving estimate ($CAD/yr) |
| `wear_delta` | REAL | Outgoing bus wear − incoming bus wear (positive = improvement) |
| `significance` | TEXT | `"HIGH"` (Δ ≥ 25) or `"MEDIUM"` (Δ 15–24) |

---

## Running the Pipeline

```bash
cd hackathon_26_drt_data_processing
uv run python build_db.py
```

**Expected console output:**
- GTFS, PRESTO, PM HotList, and Rate My Ride load counts
- Per-route summary table: route, bus count, recs, avg stress, avg wear
- Top-5 swap recommendations with wear delta and estimated saving
- `drt_fleet.db` path confirmation

**Runtime:** ~45–90 seconds. The bottleneck is haversine distance computation across 108,288 shape points. PRESTO concatenation (~6.7 M rows) is the second bottleneck; memory peaks during the concat then drops after aggregation.

**After running**, copy the DB to the Xcode bundle:
```bash
cp drt_fleet.db \
  ../LifecycleCostBalancedBusOperations/LifecycleCostBalancedBusOperations/drt_fleet.db
```

---

## Actual Results (March 2026 run)

| Metric | Value |
|---|---|
| Fleet size (buses scored) | 205 |
| Routes analysed | 39 |
| Bus-route history pairs | 2,562 |
| Unique buses in history | 184 |
| PRESTO rows processed | 6,759,265 |
| Swap recommendations | 2 |
| HIGH significance | 2 |
| MEDIUM significance | 0 |

**Why only 2 recommendations?** The constraint algorithm correctly reflects the DRT network: only 2 routes qualify as low-stress (stress < 40) — Route 216 (35.7) and Route 301 (19.6). Route 301 has only 1 bus and cannot contribute to the pool. Route 216 has 2 buses, allowing 1 to move. After Route 920 (stress 93.9) claims both pool slots, no fresh buses remain for the 7 other high-stress routes. The 2 recommendations that exist are genuine and high-quality (wear Δ 53–66 pts, est. $2,908/yr each).

**Top recommendations:**

| Bus | Route | → | Route | Wear | Δ | Stress change | Sig | Est. saving |
|---|---|---|---|---|---|---|---|---|
| 8602 | 920 | → | 216 | 82.2 | 65.8 | 93.9 → 35.7 | HIGH | $2,908/yr |
| 8605 | 920 | → | 216 | 77.9 | 52.6 | 93.9 → 35.7 | HIGH | $2,908/yr |

---

## Design Decisions & Caveats

- **Rate My Ride as route proxy.** Trip counts are a frequency proxy for current assignment, not a live dispatch record. A bus that ran Route 905 most often is assumed to currently operate Route 905. Recommendations require operational validation before implementation.
- **PM HotList aggregation to max.** Multiple PM work orders per bus (fluid, filter, inspection, etc.) are collapsed to `max()` per wear field. This captures the worst outstanding service need rather than the average.
- **PRESTO full year (Jan–Dec 2025).** All 12 monthly CSVs are concatenated before computing tap counts, eliminating the seasonal bias of any single sample week. Memory peaks at ~6.7 M rows during concat, then reduces immediately after stop-level aggregation.
- **Shape distance averaging.** Routes with inbound/outbound or express variants have multiple `shape_id` entries. The mean distance is used. A `max` approach could be substituted if variant lengths differ significantly (e.g. express vs local on the same route number).
- **Estimated savings are illustrative.** The `$500/10-point` figure is a placeholder chosen to give stakeholders an order-of-magnitude signal for prioritisation, not for budget planning. The Presentation view exposes this as an editable input so judges and stakeholders can substitute their own figure.
- **Ghost route exclusion.** Routes with `stress_score == 0` and no bus assignments are excluded from swap eligibility to prevent trivially "easy" targets from dominating recommendations.

---

**Durham College Hackathon 2026 — Durham Region Transit Challenge**

---

*“I’ve used Claude Code to support code generation, idea organization, grammar refinement, and clarity improvement only. All final content and analysis were created by me."*