-- Auto-installs the schema from sql/install.sql on first start.
MySQL.ready(function() CreateThread(function()
    local sql = LoadResourceFile(GetCurrentResourceName(), 'sql/install.sql')
    if not sql then
        print('^1[truckco] sql/install.sql missing - run it manually^0')
        TC.ready = true
        return
    end
    -- strip comments, split on ; and run each CREATE TABLE IF NOT EXISTS
    sql = sql:gsub('%-%-[^\n]*', '')
    for stmt in sql:gmatch('[^;]+') do
        if stmt:match('%S') then
            local ok, err = pcall(MySQL.query.await, stmt)
            if not ok then print('^1[truckco] schema error: ' .. tostring(err) .. '^0') end
        end
    end
    -- migrations for existing installs (no manual SQL needed)
    local function ensureColumn(tbl, col, def)
        local has = MySQL.scalar.await(
            'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            { tbl, col })
        if (has or 0) == 0 then
            MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tbl, col, def))
            print(('^3[truckco] added column %s.%s^0'):format(tbl, col))
        end
    end
    ensureColumn('truckco_companies', 'layout', 'LONGTEXT NULL')
    ensureColumn('truckco_companies', 'signs', 'LONGTEXT NULL')

    -- contracts that were mid-flight with a player when the server stopped go back to "awarded"
    MySQL.update.await("UPDATE truckco_contracts SET status = 'completed' WHERE status = 'delivered'")
    MySQL.update.await("UPDATE truckco_contracts SET status = 'awarded', employee_id = NULL, truck_id = NULL, started_at = NULL, driver_kind = NULL WHERE status IN ('assigned','in_progress') AND driver_kind = 'player'")
    MySQL.update.await("UPDATE truckco_trucks t LEFT JOIN truckco_contracts c ON c.truck_id = t.id AND c.status IN ('assigned','in_progress') SET t.status = 'available' WHERE t.status IN ('in_use','reserved') AND c.id IS NULL")
    MySQL.update.await("UPDATE truckco_employees e LEFT JOIN truckco_contracts c ON c.employee_id = e.id AND c.status IN ('assigned','in_progress') SET e.status = 'idle' WHERE e.status IN ('on_job','assigned') AND c.id IS NULL")
    TC.ready = true
    print('^2[truckco] database ready^0')
end) end)
