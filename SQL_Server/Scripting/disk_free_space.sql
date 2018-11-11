WITH CTE
AS (SELECT DISTINCT
        Drive = s.volume_mount_point,
        [Free(MB)] = CAST(s.available_bytes / 1048576.0 AS DECIMAL(32, 2))
    FROM sys.master_files f
        CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.[file_id]) s )
SELECT *
FROM CTE;