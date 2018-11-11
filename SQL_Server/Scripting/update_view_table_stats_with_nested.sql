DECLARE @ObjectName sysname = 'VIEW_NAME';
DECLARE @ObjectSchema sysname = 'dbo';
 
DECLARE @WithFullscan BIT = 1;
 
DECLARE @ExecuteUpdateStatistics BIT = 1;
 
 
---------------CODE
SET NOCOUNT ON;
 
IF NOT EXISTS (   SELECT *
                  FROM   sys.objects
                  WHERE  name = @ObjectName
                         AND schema_id = SCHEMA_ID(@ObjectSchema)
                         AND type = 'V'
              )
    THROW 50000, 'Obiekt nie istnieje lub nie jest widokiem!', 1;
 
 
DECLARE @ObjectsToProcess TABLE
    (
        id INT IDENTITY PRIMARY KEY ,
        oschema sysname ,
        oname sysname ,
        otype CHAR(2) ,
        AddedFrom NVARCHAR(MAX) NULL
    );
 
WITH ObjectsToProcess
AS ( SELECT *
     FROM   sys.dm_sql_referenced_entities(
                                              QUOTENAME(@ObjectSchema) + '.'
                                              + QUOTENAME(@ObjectName) ,
                                              'OBJECT'
                                          )
   )
INSERT INTO @ObjectsToProcess (   oschema ,
                                  oname ,
                                  otype
                              )
            SELECT DISTINCT oschema = ISNULL(tp.referenced_schema_name, 'dbo') ,
                   oname = tp.referenced_entity_name ,
                   otype = o.type
            FROM   ObjectsToProcess tp
                   JOIN sys.objects o ON tp.referenced_id = o.object_id;
 
 
DECLARE @ViewsToExpand TABLE
    (
        id INT IDENTITY PRIMARY KEY ,
        vschema sysname ,
        vname sysname ,
        Processed BIT
            DEFAULT 0
    );
 
DELETE FROM @ObjectsToProcess
OUTPUT Deleted.oschema ,
       Deleted.oname
INTO @ViewsToExpand (   vschema ,
                        vname
                    )
WHERE otype = 'V';
 
DECLARE @CurrId INT ,
        @CurrVFullName NVARCHAR(MAX);
 
 
DECLARE @NestedObjectsToProcess TABLE
    (
        id INT IDENTITY PRIMARY KEY ,
        oschema sysname ,
        oname sysname ,
        otype CHAR(2)
    );
 
 
WHILE EXISTS (   SELECT TOP 1 1
                 FROM   @ViewsToExpand
                 WHERE  Processed = 0
             )
    BEGIN
 
        SELECT TOP 1 @CurrId = id ,
               @CurrVFullName = QUOTENAME(vschema) + '.' + QUOTENAME(vname)
        FROM   @ViewsToExpand
        WHERE  Processed = 0;
 
 
 
        WITH NestedObjectsToProcess
        AS ( SELECT *
             FROM   sys.dm_sql_referenced_entities(@CurrVFullName, 'OBJECT')
           )
        INSERT INTO @NestedObjectsToProcess (   oschema ,
                                                oname ,
                                                otype
                                            )
                    SELECT DISTINCT oschema = ISNULL(
                                                        tp.referenced_schema_name ,
                                                        'dbo'
                                                    ) ,
                           oname = tp.referenced_entity_name ,
                           otype = o.type
                    FROM   NestedObjectsToProcess tp
                           JOIN sys.objects o ON tp.referenced_id = o.object_id;
 
        INSERT INTO @ViewsToExpand (   vschema ,
                                       vname
                                   )
                    SELECT oschema ,
                           oname
                    FROM   @NestedObjectsToProcess tp
                           LEFT JOIN @ViewsToExpand vte ON tp.oschema = vte.vschema
                                                           AND tp.oname = vte.vname
                    WHERE  tp.otype = 'V'
                           AND vte.id IS NULL;
 
        INSERT INTO @ObjectsToProcess (   oschema ,
                                          oname ,
                                          otype ,
                                          AddedFrom
                                      )
                    SELECT ntp.oschema ,
                           ntp.oname ,
                           ntp.otype ,
                           @CurrVFullName
                    FROM   @NestedObjectsToProcess ntp
                           LEFT JOIN @ObjectsToProcess otp ON otp.oname = ntp.oname
                                                              AND otp.oschema = ntp.oschema
                    WHERE  ntp.otype != 'V'
                           AND otp.id IS NULL;
 
 
 
        UPDATE @ViewsToExpand
        SET    Processed = 1
        WHERE  id = @CurrId;
 
    END;
 
 
/* SEKCJA PODSUMOWANIA */
DECLARE @msg NVARCHAR(MAX) ,
        @txt NVARCHAR(MAX);
DECLARE @SCRollDog CURSOR;
 
 
IF EXISTS (   SELECT TOP 1 1
              FROM   @ViewsToExpand
          )
    BEGIN
 
        SET @msg = 'Znaleziono odniesienia do następujących widoków:';
        RAISERROR(@msg, 0, 1) WITH NOWAIT;
 
        SET @SCRollDog = CURSOR LOCAL FAST_FORWARD FOR
        SELECT txt = QUOTENAME(vschema) + '.' + QUOTENAME(vname)
        FROM   @ViewsToExpand;
        OPEN @SCRollDog;
        FETCH NEXT FROM @SCRollDog
        INTO @txt;
        WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @msg = '	--> ' + @txt;
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
                FETCH NEXT FROM @SCRollDog
                INTO @txt;
            END;
        CLOSE @SCRollDog;
        DEALLOCATE @SCRollDog;
 
    END;
 
--odstep
SET @msg = CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10);
RAISERROR(@msg, 0, 1) WITH NOWAIT;
 
SET @msg = 'Tabele do aktualizacji statystyk:';
RAISERROR(@msg, 0, 1) WITH NOWAIT;
 
SET @SCRollDog = CURSOR LOCAL FAST_FORWARD FOR
SELECT txt = QUOTENAME(oschema) + '.' + QUOTENAME(oname)
             + CASE WHEN AddedFrom IS NOT NULL THEN
                        ' (wymagana przez widok: ' + AddedFrom + ')'
                    ELSE ''
               END
FROM   @ObjectsToProcess;
OPEN @SCRollDog;
FETCH NEXT FROM @SCRollDog
INTO @txt;
WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @msg = '	--> ' + @txt;
        RAISERROR(@msg, 0, 1) WITH NOWAIT;
        FETCH NEXT FROM @SCRollDog
        INTO @txt;
    END;
CLOSE @SCRollDog;
DEALLOCATE @SCRollDog;
 
SET @msg = CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10);
RAISERROR(@msg, 0, 1) WITH NOWAIT;
 
 
IF @ExecuteUpdateStatistics = 0
    BEGIN
        SET @msg = 'Skrypt aktualizujący statystyki:';
        RAISERROR(@msg, 0, 1) WITH NOWAIT;
        SET @msg = CHAR(13) + CHAR(10);
        RAISERROR(@msg, 0, 1) WITH NOWAIT;
 
        SET @SCRollDog = CURSOR LOCAL FAST_FORWARD FOR
        SELECT txt = 'UPDATE STATISTICS ' + QUOTENAME(oschema) + '.'
                     + QUOTENAME(oname)
                     + CASE WHEN @WithFullscan = 1 THEN ' WITH FULLSCAN'
                            ELSE ''
                       END
        FROM   @ObjectsToProcess;
        OPEN @SCRollDog;
        FETCH NEXT FROM @SCRollDog
        INTO @txt;
        WHILE @@FETCH_STATUS = 0
            BEGIN
 
                RAISERROR(@txt, 0, 1) WITH NOWAIT;
                FETCH NEXT FROM @SCRollDog
                INTO @txt;
            END;
        CLOSE @SCRollDog;
        DEALLOCATE @SCRollDog;
 
        SET @msg = CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10);
        RAISERROR(@msg, 0, 1) WITH NOWAIT;
    END;
ELSE --IF @ExecuteUpdateStatistics = 1
    BEGIN
        DECLARE @ObjCount_s NVARCHAR(MAX) = (   SELECT CAST(COUNT(*) AS NVARCHAR(MAX))
                                                FROM   @ObjectsToProcess
                                            ) ,
                @i INT = 1;
        DECLARE @DateTimeStart DATETIME2(0) ,
                @DateTimeStop DATETIME2(0) ,
                @TotalDateTimeStart DATETIME2(0) = GETDATE() ,
                @TotalDateTimeStop DATETIME2(0);
 
        DECLARE @CurrObject NVARCHAR(MAX);
 
 
 
        SET @SCRollDog = CURSOR LOCAL FAST_FORWARD FOR
        SELECT txt = 'UPDATE STATISTICS ' + QUOTENAME(oschema) + '.'
                     + QUOTENAME(oname)
                     + CASE WHEN @WithFullscan = 1 THEN ' WITH FULLSCAN'
                            ELSE ''
                       END ,
               CurrObject = QUOTENAME(oschema) + '.' + QUOTENAME(oname)
        FROM   @ObjectsToProcess;
        OPEN @SCRollDog;
        FETCH NEXT FROM @SCRollDog
        INTO @txt ,
             @CurrObject;
        WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @DateTimeStart = GETDATE();
                SET @msg = 'Processing: ' + @CurrObject + ' ('
                           + CAST(@i AS NVARCHAR(MAX)) + '/' + @ObjCount_s
                           + ') , start: '
                           + CAST(@DateTimeStart AS NVARCHAR(MAX));
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
 
                EXEC ( @txt );
 
                SET @DateTimeStop = GETDATE();
                SET @msg = 'Processing: ' + @CurrObject + ' DONE in: '
                           + CONVERT(
                                        NVARCHAR ,
                                        DATEADD(
                                                   ss ,
                                                   DATEDIFF(
                                                               ss ,
                                                               @DateTimeStart ,
                                                               @DateTimeStop
                                                           ) ,
                                                   0
                                               ) ,
                                        108
                                    ) + ' , stop: '
                           + CAST(@DateTimeStop AS NVARCHAR(MAX));
 
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
 
                RAISERROR('', 0, 1) WITH NOWAIT;
 
                FETCH NEXT FROM @SCRollDog
                INTO @txt ,
                     @CurrObject;
                SET @i += 1;
            END;
        CLOSE @SCRollDog;
        DEALLOCATE @SCRollDog;
 
        SET @TotalDateTimeStop = GETDATE();
 
        SET @msg = CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10);
        RAISERROR(@msg, 0, 1) WITH NOWAIT;
 
        SET @msg = 'PROCESSING DONE! Total time: '
                   + CONVERT(
                                NVARCHAR ,
                                DATEADD(
                                           ss ,
                                           DATEDIFF(
                                                       ss ,
                                                       @TotalDateTimeStart ,
                                                       @TotalDateTimeStop
                                                   ) ,
                                           0
                                       ) ,
                                108
                            );
        RAISERROR(@msg, 0, 1) WITH NOWAIT;
 
    END;