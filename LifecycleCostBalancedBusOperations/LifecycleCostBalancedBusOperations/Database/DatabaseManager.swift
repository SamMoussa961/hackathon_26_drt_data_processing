import Foundation
import SQLite3

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?

    private init() {
        guard let url = Bundle.main.url(forResource: "drt_fleet", withExtension: "db") else {
            print("DatabaseManager: drt_fleet.db not found in bundle")
            return
        }
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            print("DatabaseManager: open failed – \(msg)")
            db = nil
        } else {
            print("DatabaseManager: opened \(url.path)")
        }
    }

    deinit { sqlite3_close(db) }

    // MARK: - Buses

    func fetchBuses() -> [Bus] {
        guard let db else { return [] }
        let sql = """
            SELECT alias, lastreading, unitstogo, unitslate, dayslate,
                   wear_score, current_route
            FROM buses
            ORDER BY wear_score DESC
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("fetchBuses error: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        var rows: [Bus] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(Bus(
                alias:        str(stmt, 0),
                lastreading:  sqlite3_column_double(stmt, 1),
                unitstogo:    sqlite3_column_double(stmt, 2),
                unitslate:    sqlite3_column_double(stmt, 3),
                dayslate:     sqlite3_column_double(stmt, 4),
                wearScore:    sqlite3_column_double(stmt, 5),
                currentRoute: strOpt(stmt, 6)
            ))
        }
        return rows
    }

    // MARK: - Routes

    func fetchRoutes() -> [Route] {
        guard let db else { return [] }
        let sql = """
            SELECT route_id, route_short_name, stop_count,
                   shape_distance_km, avg_taps_per_stop, stress_score
            FROM routes
            ORDER BY stress_score DESC
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        var rows: [Route] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(Route(
                routeId:         str(stmt, 0),
                routeShortName:  str(stmt, 1),
                stopCount:       Int(sqlite3_column_int(stmt, 2)),
                shapeDistanceKm: sqlite3_column_double(stmt, 3),
                avgTapsPerStop:  sqlite3_column_double(stmt, 4),
                stressScore:     sqlite3_column_double(stmt, 5)
            ))
        }
        return rows
    }

    // MARK: - Swap recommendations

    func fetchSwapRecs() -> [SwapRecommendation] {
        guard let db else { return [] }
        let sql = """
            SELECT bus_alias, current_route, proposed_route,
                   wear_score, current_stress, proposed_stress,
                   swap_score, estimated_annual_saving_cad,
                   COALESCE(wear_delta, 0.0),
                   COALESCE(significance, 'MEDIUM')
            FROM swap_recs
            ORDER BY swap_score DESC
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        var rows: [SwapRecommendation] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(SwapRecommendation(
                busAlias:                 str(stmt, 0),
                currentRoute:             str(stmt, 1),
                proposedRoute:            str(stmt, 2),
                wearScore:                sqlite3_column_double(stmt, 3),
                currentStress:            sqlite3_column_double(stmt, 4),
                proposedStress:           sqlite3_column_double(stmt, 5),
                swapScore:                sqlite3_column_double(stmt, 6),
                estimatedAnnualSavingCAD: sqlite3_column_double(stmt, 7),
                wearDelta:                sqlite3_column_double(stmt, 8),
                significance:             str(stmt, 9)
            ))
        }
        return rows
    }

    // MARK: - Bus count per route (from bus_route_hist most-frequent assignment)

    func fetchRouteBusCounts() -> [String: Int] {
        guard let db else { return [:] }
        let sql = """
            SELECT route_short_name, COUNT(DISTINCT vehicle_label) AS bus_count
            FROM (
                SELECT vehicle_label,
                       route_short_name,
                       ROW_NUMBER() OVER (
                           PARTITION BY vehicle_label
                           ORDER BY trip_count DESC
                       ) AS rn
                FROM bus_route_hist
            )
            WHERE rn = 1
            GROUP BY route_short_name
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        var result: [String: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            result[str(stmt, 0)] = Int(sqlite3_column_int(stmt, 1))
        }
        return result
    }

    // MARK: - Helpers

    private func str(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: c)
    }

    private func strOpt(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL,
              let c = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: c)
    }
}
