"""
Lifecycle Cost-Balanced Bus Operations  (LCBO) — Step 1: Data Pipeline
Builds drt_fleet.db (SQLite) with fleet wear scores, route stress scores, and swap recommendations.
"""

import os
import math
import sqlite3
import warnings
import pandas as pd
from dotenv import load_dotenv

warnings.filterwarnings("ignore")

# Load paths from .env (located next to this script)
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(_SCRIPT_DIR, ".env"))

GTFS_DIR  = os.environ["GTFS_DIR"]
DATA_DIR  = os.environ["DATA_DIR"]
RMR_PATH  = os.environ["RMR_PATH"]
PM_PATH   = os.environ["PM_PATH"]
PRESTO_DIR = os.environ["PRESTO_DIR"]
DB_PATH   = os.environ["DB_PATH"]

# ── helpers ──────────────────────────────────────────────────────────────────

def normalise(series: pd.Series) -> pd.Series:
    """Min-max normalise a series to 0-100."""
    mn, mx = series.min(), series.max()
    if mx == mn:
        return pd.Series([50.0] * len(series), index=series.index)
    return (series - mn) / (mx - mn) * 100


def haversine_km(lat1, lon1, lat2, lon2):
    R = 6371.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def warn_nulls(df: pd.DataFrame, join_name: str, col: str, threshold: float = 0.30):
    null_frac = df[col].isna().mean()
    if null_frac > threshold:
        print(f"  WARNING: {join_name} — {null_frac:.1%} null in '{col}' ({df[col].isna().sum()} rows)")


# ── 1. Rate My Ride ──────────────────────────────────────────────────────────

print("\n=== Loading Rate My Ride ===")
try:
    rmr = pd.read_csv(RMR_PATH, usecols=["vehicle_label", "route_short_name", "trip_id"],
                      low_memory=False)
    print(f"  Loaded {len(rmr):,} rows from {RMR_PATH}")
    print(f"  Columns: {list(rmr.columns)}")
except Exception as e:
    print(f"  ERROR loading Rate My Ride: {e}")
    rmr = pd.DataFrame(columns=["vehicle_label", "route_short_name", "trip_id"])

# ── 2. GTFS ──────────────────────────────────────────────────────────────────

print("\n=== Loading GTFS ===")
stops      = pd.read_csv(os.path.join(GTFS_DIR, "stops.txt"))
routes     = pd.read_csv(os.path.join(GTFS_DIR, "routes.txt"))
trips      = pd.read_csv(os.path.join(GTFS_DIR, "trips.txt"))
stop_times = pd.read_csv(os.path.join(GTFS_DIR, "stop_times.txt"),
                         usecols=["trip_id", "stop_id"])
shapes     = pd.read_csv(os.path.join(GTFS_DIR, "shapes.txt"))
print(f"  stops={len(stops):,}  routes={len(routes):,}  trips={len(trips):,}  "
      f"stop_times={len(stop_times):,}  shapes={len(shapes):,}")

# Ensure consistent types for join
stops["stop_id"] = stops["stop_id"].astype(str)
stop_times["stop_id"] = stop_times["stop_id"].astype(str)

# ── 3a. stop_count per route ──────────────────────────────────────────────────

print("\n=== Computing stop_count per route ===")
# trip_id → route_id
trip_route = trips[["trip_id", "route_id"]].drop_duplicates()
# stop_times → route_id
st_with_route = stop_times.merge(trip_route, on="trip_id", how="left")
warn_nulls(st_with_route, "stop_times→trips join", "route_id")

stop_count = (
    st_with_route.dropna(subset=["route_id"])
    .groupby("route_id")["stop_id"]
    .nunique()
    .reset_index()
    .rename(columns={"stop_id": "stop_count"})
)
print(f"  Routes with stop counts: {len(stop_count)}")

# ── 3b. shape_distance_km per route ──────────────────────────────────────────

print("\n=== Computing shape distances ===")
shapes_sorted = shapes.sort_values(["shape_id", "shape_pt_sequence"])

def shape_distance(group):
    pts = group[["shape_pt_lat", "shape_pt_lon"]].values
    dist = sum(
        haversine_km(pts[i][0], pts[i][1], pts[i+1][0], pts[i+1][1])
        for i in range(len(pts) - 1)
    )
    return dist

shape_km = (
    shapes_sorted.groupby("shape_id")
    .apply(shape_distance)
    .reset_index()
    .rename(columns={0: "shape_distance_km"})
)
print(f"  Unique shapes processed: {len(shape_km)}")

# Join shape_id → route_id via trips (one shape can map to multiple trips/routes)
shape_route = trips[["route_id", "shape_id"]].drop_duplicates()
shape_route = shape_route.merge(shape_km, on="shape_id", how="left")
# Average shape distance per route (routes may have multiple shapes for variants)
route_distance = (
    shape_route.groupby("route_id")["shape_distance_km"]
    .mean()
    .reset_index()
)
print(f"  Routes with shape distance: {len(route_distance)}")

# ── 3c. avg_taps_per_stop per route from PRESTO sample ──────────────────────

print("\n=== Computing avg_taps_per_stop from PRESTO (full year) ===")
presto_files = sorted(
    f for f in os.listdir(PRESTO_DIR)
    if f.endswith(".csv") and not f.startswith(".")
)
print(f"  Found {len(presto_files)} monthly PRESTO files: {presto_files}")
try:
    presto_chunks = []
    for fname in presto_files:
        chunk = pd.read_csv(os.path.join(PRESTO_DIR, fname), low_memory=False)
        presto_chunks.append(chunk)
    presto = pd.concat(presto_chunks, ignore_index=True)
    print(f"  PRESTO columns: {list(presto.columns)}")
    print(f"  PRESTO rows (all months): {len(presto):,}")
except Exception as e:
    print(f"  ERROR loading PRESTO monthly files: {e}")
    presto = pd.DataFrame()

if len(presto) > 0:
    # trxlocationid arrives as float (e.g. 3633.0) — normalise to integer string for join
    presto["stop_code_str"] = (
        pd.to_numeric(presto["trxlocationid"], errors="coerce")
        .dropna()
        .astype(int)
        .astype(str)
    )
    taps_per_stop = (
        presto.dropna(subset=["stop_code_str"])
        .groupby("stop_code_str")
        .size()
        .reset_index(name="tap_count")
    )
    # PRESTO stop_code_str → GTFS stops.stop_code → stops.stop_id → stop_times
    stops["stop_code_str"] = stops["stop_code"].astype(str)
    stop_code_to_id = stops[["stop_code_str", "stop_id"]].drop_duplicates()
    taps_with_id = taps_per_stop.merge(stop_code_to_id, on="stop_code_str", how="left")
    warn_nulls(taps_with_id, "PRESTO→stops join", "stop_id")
    taps_with_id = taps_with_id.dropna(subset=["stop_id"])
    taps_with_id["stop_id"] = taps_with_id["stop_id"].astype(str)

    # Join to stop_times to get route_id
    st_taps = stop_times.merge(
        taps_with_id[["stop_id", "tap_count"]], on="stop_id", how="left"
    )
    st_taps = st_taps.merge(trip_route, on="trip_id", how="left")
    warn_nulls(st_taps, "PRESTO→stop_times join", "tap_count")
    warn_nulls(st_taps, "stop_times→trips join", "route_id")

    # avg taps per stop per route
    avg_taps = (
        st_taps.dropna(subset=["route_id"])
        .groupby("route_id")["tap_count"]
        .mean()
        .reset_index()
        .rename(columns={"tap_count": "avg_taps_per_stop"})
    )
    print(f"  Routes with tap data: {len(avg_taps)}")
else:
    avg_taps = pd.DataFrame(columns=["route_id", "avg_taps_per_stop"])
    print("  WARNING: No PRESTO data — avg_taps_per_stop will be 0")

# ── 3e. RouteStress ──────────────────────────────────────────────────────────

print("\n=== Computing RouteStress ===")
route_stress = (
    routes[["route_id", "route_short_name"]]
    .merge(stop_count, on="route_id", how="left")
    .merge(route_distance, on="route_id", how="left")
    .merge(avg_taps, on="route_id", how="left")
)
route_stress["stop_count"]        = route_stress["stop_count"].fillna(0)
route_stress["shape_distance_km"] = route_stress["shape_distance_km"].fillna(0)
route_stress["avg_taps_per_stop"] = route_stress["avg_taps_per_stop"].fillna(0)

W1, W2, W3 = 0.3, 0.4, 0.3
route_stress["raw_stress"] = (
    normalise(route_stress["shape_distance_km"]) * W1 +
    normalise(route_stress["stop_count"]) * W2 +
    normalise(route_stress["avg_taps_per_stop"]) * W3
)
route_stress["stress_score"] = normalise(route_stress["raw_stress"])
print(f"  Routes scored: {len(route_stress)}")
print(f"  Stress score range: {route_stress['stress_score'].min():.1f} – {route_stress['stress_score'].max():.1f}")

# ── 4. WearScore per bus from PM HotList ─────────────────────────────────────

print("\n=== Computing WearScore ===")
pm = pd.read_csv(PM_PATH, low_memory=False)
print(f"  PM HotList columns: {list(pm.columns)}")
print(f"  PM HotList rows: {len(pm):,}")

# Keep only rows with valid numeric alias (bus number); drop header-bleed rows like "String"
pm = pm.dropna(subset=["alias"])
pm["alias"] = pm["alias"].astype(str).str.strip()
pm = pm[pm["alias"].str.match(r"^\d+$")]

# Numeric coercion
for col in ["lastreading", "unitslate", "dayslate"]:
    pm[col] = pd.to_numeric(pm[col], errors="coerce").fillna(0)

# Aggregate per bus (multiple PM rows possible per bus — take max wear indicators)
buses = (
    pm.groupby("alias")
    .agg(
        lastreading=("lastreading", "max"),
        unitstogo=("unitstogo", "min"),
        unitslate=("unitslate", "max"),
        dayslate=("dayslate", "max"),
    )
    .reset_index()
)

# Raw WearScore
buses["raw_wear"] = (
    buses["lastreading"] * 0.4 +
    buses["unitslate"]   * 0.3 +
    buses["dayslate"]    * 0.3
)
buses["wear_score"] = normalise(buses["raw_wear"])
print(f"  Buses scored: {len(buses)}")
print(f"  Wear score range: {buses['wear_score'].min():.1f} – {buses['wear_score'].max():.1f}")

# ── 5. Bus↔Route history from Rate My Ride ───────────────────────────────────

print("\n=== Building bus↔route history ===")
if len(rmr) > 0:
    rmr_clean = rmr.dropna(subset=["vehicle_label"])
    # vehicle_label comes in as float (e.g. 8616.0) — normalise to integer string
    rmr_clean["vehicle_label"] = (
        pd.to_numeric(rmr_clean["vehicle_label"], errors="coerce")
        .dropna()
        .astype(int)
        .astype(str)
    )
    rmr_clean = rmr_clean.dropna(subset=["vehicle_label"])
    bus_route_hist = (
        rmr_clean.groupby(["vehicle_label", "route_short_name"])
        .size()
        .reset_index(name="trip_count")
        .sort_values("trip_count", ascending=False)
    )
    print(f"  Bus-route pairs: {len(bus_route_hist):,}")
    print(f"  Unique buses in history: {bus_route_hist['vehicle_label'].nunique():,}")
    print(f"  Unique routes in history: {bus_route_hist['route_short_name'].nunique():,}")

    # Most frequent current route per bus
    most_freq_route = (
        bus_route_hist.sort_values("trip_count", ascending=False)
        .groupby("vehicle_label")
        .first()
        .reset_index()[["vehicle_label", "route_short_name"]]
        .rename(columns={"route_short_name": "current_route"})
    )
else:
    bus_route_hist = pd.DataFrame(columns=["vehicle_label", "route_short_name", "trip_count"])
    most_freq_route = pd.DataFrame(columns=["vehicle_label", "current_route"])
    print("  WARNING: No Rate My Ride data — bus_route_hist will be empty")

# ── 6. Swap recommendations ──────────────────────────────────────────────────

print("\n=== Generating swap recommendations (improved algorithm) ===")

COST_PER_POINT = 500   # $/yr per 10-pt stress reduction (adjustable in UI)
HIGH_STRESS_THRESHOLD = 60
LOW_STRESS_THRESHOLD  = 40
MIN_WEAR_DELTA        = 10  # minimum wear difference to be significant

# ── 6a. Join buses → current route → current stress ──────────────────────────

route_stress_lookup = route_stress.set_index("route_short_name")["stress_score"].to_dict()

buses_with_route = buses.merge(
    most_freq_route,
    left_on="alias", right_on="vehicle_label",
    how="left"
)
warn_nulls(buses_with_route, "buses→route_history join", "current_route")

buses_with_route["current_stress"] = (
    buses_with_route["current_route"]
    .map(route_stress_lookup)
    .fillna(50.0)
)

# ── 6b. Bus count per route (from most-frequent-route assignments) ────────────

route_bus_count = (
    buses_with_route.dropna(subset=["current_route"])
    .groupby("current_route")
    .size()
    .to_dict()
)

# ── 6c. Build route→buses lookup (sorted wear desc per route) ─────────────────

route_to_buses: dict[str, list[dict]] = {}
for route, grp in buses_with_route.dropna(subset=["current_route"]).groupby("current_route"):
    sorted_grp = grp.sort_values("wear_score", ascending=False)
    route_to_buses[str(route)] = sorted_grp[["alias","wear_score","current_route","current_stress"]].to_dict("records")

# Exclude routes: stress == 0 AND no buses assigned (ghost routes)
excluded_routes = {
    r for r, s in route_stress_lookup.items()
    if s == 0 and r not in route_bus_count
}

# ── 6d. Classify routes ───────────────────────────────────────────────────────

high_stress_routes = sorted(
    [r for r, s in route_stress_lookup.items()
     if s > HIGH_STRESS_THRESHOLD
     and r not in excluded_routes
     and r in route_to_buses],
    key=lambda r: route_stress_lookup[r], reverse=True
)

low_stress_routes = sorted(
    [r for r, s in route_stress_lookup.items()
     if s < LOW_STRESS_THRESHOLD
     and r not in excluded_routes
     and r in route_to_buses],
    key=lambda r: route_stress_lookup[r]  # ascending: easiest first
)

# Pool of fresh buses available from low-stress routes (sorted wear ascending)
low_stress_bus_pool = sorted(
    [
        dict(**b, route_stress=route_stress_lookup.get(b["current_route"], 0))
        for route in low_stress_routes
        for b in route_to_buses.get(route, [])
    ],
    key=lambda b: b["wear_score"]
)

print(f"  High-stress routes (>{HIGH_STRESS_THRESHOLD}): {len(high_stress_routes)}")
print(f"  Low-stress routes  (<{LOW_STRESS_THRESHOLD}): {len(low_stress_routes)}")
print(f"  Fresh-bus pool size: {len(low_stress_bus_pool)}")

# ── 6e. Generate swap recommendations ─────────────────────────────────────────

used_buses:  set[str] = set()
recs_per_route: dict[str, int] = {}
swap_recs = []

# ---- HIGH-stress route swaps ------------------------------------------------
# For each worn bus on a high-stress route, find a fresher bus from a low-stress route.
for route in high_stress_routes:
    buses_here = route_to_buses.get(route, [])
    route_count = route_bus_count.get(route, 0)
    current_stress = route_stress_lookup.get(route, 0)

    if route_count <= 1:
        continue  # cannot leave the route with 0 buses

    # The most-worn bus is the candidate to move OUT to an easier route
    most_worn_here = max(b["wear_score"] for b in buses_here)

    for bus in buses_here:
        alias = bus["alias"]
        ws    = bus["wear_score"]

        if alias in used_buses:
            continue
        if ws != most_worn_here:
            continue  # only consider swapping the most-worn bus out
        if recs_per_route.get(route, 0) >= route_count:
            break

        # Find the freshest available bus from a low-stress route
        for candidate in low_stress_bus_pool:
            c_alias = candidate["alias"]
            c_ws    = candidate["wear_score"]
            c_route = candidate["current_route"]

            if c_alias in used_buses:
                continue
            if c_route == route:
                continue
            if route_bus_count.get(c_route, 0) <= 1:
                continue  # would empty that route

            wear_delta = ws - c_ws
            if wear_delta < MIN_WEAR_DELTA:
                continue  # try next candidate — higher wear_score = bigger delta

            sig = "HIGH" if wear_delta >= 25 else "MEDIUM"
            proposed_stress = route_stress_lookup.get(c_route, 0)
            swap_score  = ws + current_stress - proposed_stress
            stress_delta = current_stress - proposed_stress
            est_saving  = max(0.0, stress_delta / 10 * COST_PER_POINT)

            swap_recs.append({
                "bus_alias":                   alias,
                "current_route":               route,
                "proposed_route":              c_route,
                "wear_score":                  round(ws, 2),
                "current_stress":              round(current_stress, 2),
                "proposed_stress":             round(proposed_stress, 2),
                "swap_score":                  round(swap_score, 2),
                "estimated_annual_saving_cad": round(est_saving, 2),
                "wear_delta":                  round(wear_delta, 2),
                "significance":                sig,
            })

            used_buses.add(alias)
            used_buses.add(c_alias)
            recs_per_route[route] = recs_per_route.get(route, 0) + 1
            break  # matched; move to next high-stress route

        break  # only process the most-worn bus per route per pass

# ---- LOW-stress route swaps -------------------------------------------------
# For the most-worn bus on each low-stress route, find the gentlest high-stress
# route where that bus would be the lowest-wear bus — fresh blood for a worn fleet.
for route in low_stress_routes:
    buses_here = route_to_buses.get(route, [])
    route_count = route_bus_count.get(route, 0)
    current_stress = route_stress_lookup.get(route, 0)

    if route_count <= 1:
        continue

    # Most-worn available bus on this low-stress route
    most_worn = next((b for b in buses_here if b["alias"] not in used_buses), None)
    if most_worn is None:
        continue

    mw_alias = most_worn["alias"]
    mw_ws    = most_worn["wear_score"]

    # Find the gentlest qualifying high-stress route (lowest stress > threshold)
    # where mw_ws < every current bus on that route (so it becomes the freshest)
    for target_route in sorted(high_stress_routes, key=lambda r: route_stress_lookup[r]):
        if target_route == route:
            continue

        target_buses = route_to_buses.get(target_route, [])
        if not target_buses:
            continue

        available_target = [b for b in target_buses if b["alias"] not in used_buses]
        if not available_target:
            continue

        target_wears = [b["wear_score"] for b in available_target]
        if mw_ws >= min(target_wears):
            continue  # mw_ws is NOT the lowest — skip

        # The swapping-out bus from the target is its least-worn available bus
        target_out = min(available_target, key=lambda b: b["wear_score"])
        wear_delta = target_out["wear_score"] - mw_ws
        if wear_delta < MIN_WEAR_DELTA:
            continue  # not significant enough

        sig = "HIGH" if wear_delta >= 25 else "MEDIUM"
        target_stress = route_stress_lookup.get(target_route, 0)
        swap_score    = mw_ws + current_stress - target_stress

        swap_recs.append({
            "bus_alias":                   mw_alias,
            "current_route":               route,
            "proposed_route":              target_route,
            "wear_score":                  round(mw_ws, 2),
            "current_stress":              round(current_stress, 2),
            "proposed_stress":             round(target_stress, 2),
            "swap_score":                  round(swap_score, 2),
            "estimated_annual_saving_cad": 0.0,  # stress increases; no saving
            "wear_delta":                  round(wear_delta, 2),
            "significance":                sig,
        })

        used_buses.add(mw_alias)
        used_buses.add(target_out["alias"])
        break  # one recommendation per low-stress route

# ── 6f. Finalise swap DataFrame ───────────────────────────────────────────────

swap_df = pd.DataFrame(swap_recs) if swap_recs else pd.DataFrame(
    columns=["bus_alias","current_route","proposed_route","wear_score",
             "current_stress","proposed_stress","swap_score",
             "estimated_annual_saving_cad","wear_delta","significance"]
)
if len(swap_df) > 0:
    swap_df = swap_df.sort_values("swap_score", ascending=False)
print(f"  Swap recommendations generated: {len(swap_df)}")
if len(swap_df) > 0:
    high_ct = (swap_df["significance"] == "HIGH").sum()
    med_ct  = (swap_df["significance"] == "MEDIUM").sum()
    print(f"    HIGH significance: {high_ct}   MEDIUM significance: {med_ct}")

# ── 7. Write SQLite ──────────────────────────────────────────────────────────

print(f"\n=== Writing {DB_PATH} ===")

# Prepare buses table — add current_route
buses_out = buses_with_route[[
    "alias", "lastreading", "unitstogo", "unitslate", "dayslate", "wear_score", "current_route"
]].copy()

# Prepare routes table
routes_out = route_stress[[
    "route_id", "route_short_name", "stop_count", "shape_distance_km", "avg_taps_per_stop", "stress_score"
]].copy()

with sqlite3.connect(DB_PATH) as con:
    buses_out.to_sql("buses", con, if_exists="replace", index=False)
    routes_out.to_sql("routes", con, if_exists="replace", index=False)
    bus_route_hist.to_sql("bus_route_hist", con, if_exists="replace", index=False)
    swap_df.to_sql("swap_recs", con, if_exists="replace", index=False)
    print("  Tables written: buses, routes, bus_route_hist, swap_recs")

# ── 8. Summary ───────────────────────────────────────────────────────────────

print("\n" + "=" * 70)
print("  DRT FLEET EQUALIZER — BUILD SUMMARY")
print("=" * 70)
print(f"  Fleet size (buses scored):     {len(buses):>6,}")
print(f"  Routes analysed:               {len(routes_out):>6,}")
print(f"  Bus-route history pairs:       {len(bus_route_hist):>6,}")
print(f"  Swap recommendations:          {len(swap_df):>6,}")
if len(swap_df) > 0:
    high_ct = (swap_df["significance"] == "HIGH").sum()
    med_ct  = (swap_df["significance"] == "MEDIUM").sum()
    print(f"    HIGH significance:           {high_ct:>6,}")
    print(f"    MEDIUM significance:         {med_ct:>6,}")
print()

# Per-route summary
print("  PER-ROUTE SUMMARY:")
print(f"  {'Route':<12} {'Buses':>6} {'Recs':>6} {'AvgStress':>10} {'AvgWear':>9}")
print("  " + "-" * 48)

all_routes_names = sorted(route_stress["route_short_name"].unique())
for r in all_routes_names:
    bus_cnt  = route_bus_count.get(r, 0)
    if bus_cnt == 0:
        continue  # skip routes with no buses
    rec_cnt  = len(swap_df[swap_df["current_route"] == r]) if len(swap_df) > 0 else 0
    avg_s    = route_stress_lookup.get(r, 0)
    buses_on = route_to_buses.get(r, [])
    avg_w    = (sum(b["wear_score"] for b in buses_on) / len(buses_on)) if buses_on else 0.0
    print(f"  {r:<12} {bus_cnt:>6} {rec_cnt:>6} {avg_s:>10.1f} {avg_w:>9.1f}")

print()
print("  TOP 5 SWAP RECOMMENDATIONS:")
print("  (Estimated savings: $500/yr per 10-pt stress reduction — illustrative)")
print()
top5 = swap_df.head(5) if len(swap_df) > 0 else pd.DataFrame()
for _, row in top5.iterrows():
    print(f"  Bus {str(row['bus_alias']):>6s}  |  "
          f"{str(row['current_route']):>5s} → {str(row['proposed_route']):<5s}  |  "
          f"Wear={row['wear_score']:5.1f}  Δ={row['wear_delta']:4.1f}  "
          f"Stress {row['current_stress']:5.1f}→{row['proposed_stress']:5.1f}  |  "
          f"Sig={row['significance']:6s}  SwapScore={row['swap_score']:6.1f}  |  "
          f"Est. saving: ${row['estimated_annual_saving_cad']:,.0f}/yr")
print()
print(f"  Database written to: {DB_PATH}")
print("=" * 70)
