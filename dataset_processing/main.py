import sqlite3

conn = sqlite3.connect("drt_fleet.db")
conn.row_factory = sqlite3.Row


def query(sql, params=()):
    cur = conn.execute(sql, params)
    rows = cur.fetchall()
    if not rows:
        print("(no results)")
        return
    cols = rows[0].keys()
    col_width = 20
    print("  ".join(c.ljust(col_width) for c in cols))
    print("-" * (col_width * len(cols) + 2 * (len(cols) - 1)))
    for row in rows:
        print("  ".join(str(row[c] if row[c] is not None else "").ljust(col_width) for c in cols))
    print(f"\n{len(rows)} row(s)\n")


print("Buses:")
query("""
    SELECT
    significance,
    COUNT(*)                              AS rec_count,
    ROUND(AVG(wear_score), 1)             AS avg_bus_wear,
    ROUND(AVG(wear_delta), 1)             AS avg_wear_delta,
    ROUND(AVG(current_stress), 1)         AS avg_current_stress,
    ROUND(AVG(proposed_stress), 1)        AS avg_proposed_stress,
    ROUND(AVG(current_stress - proposed_stress), 1) AS avg_stress_reduction,
    ROUND(SUM(estimated_annual_saving_cad), 0) AS total_est_saving_cad
FROM swap_recs
GROUP BY significance
ORDER BY rec_count DESC;
""")

#print("Routes:")
#query("""
#    SELECT * FROM routes;
#""")

#print("bus_route_hist:")
#query("""
#    SELECT * FROM bus_route_hist;
#""")

#print("swap_recs")
#query("""
#    SELECT * FROM swap_recs;
#""")