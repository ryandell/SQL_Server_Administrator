SELECT  f.NAME AS file_group_name,
        SCHEMA_NAME(t.schema_id) AS table_schema,
        t.name AS table_name,
        p.partition_number,
        ISNULL(CAST(left_prv.value AS VARCHAR(MAX))+ CASE WHEN pf.boundary_value_on_right = 0 THEN ' < '
               ELSE ' <= '
          END , '-INF < ')
        + 'X' + ISNULL(CASE WHEN pf.boundary_value_on_right = 0 THEN ' <= '
                           ELSE ' < '
                      END + CAST(right_prv.value AS NVARCHAR(MAX)), ' < INF') AS range_desc,
        pf.boundary_value_on_right,
        ps.name AS partition_schem_name,
        pf.name AS partition_function_name,
        left_prv.value AS left_boundary,
        right_prv.value AS right_boundary
FROM    sys.partitions p
JOIN    sys.tables t
        ON p.object_id = t.object_id
JOIN    sys.indexes i
        ON p.object_id = i.object_id
        AND p.index_id = i.index_id
JOIN    sys.allocation_units au
        ON p.hobt_id = au.container_id
JOIN    sys.filegroups f
        ON au.data_space_id = f.data_space_id
LEFT JOIN    sys.partition_schemes ps
        ON ps.data_space_id = i.data_space_id
LEFT JOIN    sys.partition_functions pf
        ON ps.function_id = pf.function_id
LEFT JOIN sys.partition_range_values left_prv
        ON left_prv.function_id = ps.function_id
           AND left_prv.boundary_id + 1 = p.partition_number
LEFT JOIN sys.partition_range_values right_prv
        ON right_prv.function_id = ps.function_id
           AND right_prv.boundary_id = p.partition_number