DECLARE @Napis NVARCHAR(MAX) = N'HEADLINE TEXT';
DECLARE @MinimumLength INT = 64;

DECLARE @MSG NVARCHAR(MAX);
DECLARE @Offset INT = 8;
DECLARE @Even BIT = CASE WHEN LEN(@Napis) % 2 = 0 THEN 1
                         ELSE 0
                    END;

DECLARE @nl NCHAR(2) = CHAR(13) + CHAR(10);
DECLARE @LineLength INT;
PRINT @Even;

IF LEN(@Napis) > @MinimumLength
    SET @MinimumLength = LEN(@Napis) + @Offset;
SET @MSG = N'/' + REPLICATE('*', @MinimumLength) + N'/';
SET @LineLength = LEN(@MSG);

SET @MSG += @nl;

SET @MSG += N'/*' + REPLICATE(' ', ( @LineLength - 4 - LEN(@Napis)) / 2)
            + CASE                                                              WHEN @Even = 0 THEN
                                                                                    ' '
                                                                                ELSE
                                                                                    ''
              END + +@Napis
            + REPLICATE(' ', ( @LineLength - 4 - LEN(@Napis)) / 2) + N'*/'
            + @nl;
SET @MSG += N'/' + REPLICATE('*', @MinimumLength) + N'/';

PRINT @MSG;