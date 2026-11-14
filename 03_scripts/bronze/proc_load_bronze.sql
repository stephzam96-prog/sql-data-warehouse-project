/*
===============================================================================
Stored Procedure: bronze.load_bronze
Propósito: Carga los 6 CSV en las tablas Bronze (Truncate & Insert, carga
           completa, sin transformaciones).
Uso:
    EXEC bronze.load_bronze @base_path = 'C:\ruta\a\01_datasets\';
Parámetro:
    @base_path  Carpeta que contiene source_crm\ y source_erp\ (debe terminar
                en '\'). IMPORTANTE: la ruta se lee DESDE EL SERVIDOR SQL, así
                que la cuenta del servicio de SQL Server necesita permiso de
                lectura en esa carpeta (si falla, copia 01_datasets a algo como
                C:\sql-data-warehouse-project\01_datasets\).
Nota: los CSV usan fin de línea de Windows (CRLF) -> ROWTERMINATOR = '0x0d0a'.
===============================================================================
*/

USE DataWarehouse;
GO

CREATE OR ALTER PROCEDURE bronze.load_bronze
    @base_path NVARCHAR(400) = N'C:\sql-data-warehouse-project\01_datasets\'
AS
BEGIN
    DECLARE @start_time DATETIME, @end_time DATETIME,
            @batch_start DATETIME = GETDATE(), @sql NVARCHAR(MAX);

    DECLARE @files TABLE (
        ord INT, tbl NVARCHAR(100), rel_path NVARCHAR(200)
    );
    INSERT INTO @files VALUES
        (1, 'bronze.crm_cust_info',     'source_crm\cust_info.csv'),
        (2, 'bronze.crm_prd_info',      'source_crm\prd_info.csv'),
        (3, 'bronze.crm_sales_details', 'source_crm\sales_details.csv'),
        (4, 'bronze.erp_cust_az12',     'source_erp\CUST_AZ12.csv'),
        (5, 'bronze.erp_loc_a101',      'source_erp\LOC_A101.csv'),
        (6, 'bronze.erp_px_cat_g1v2',   'source_erp\PX_CAT_G1V2.csv');

    DECLARE @ord INT = 1, @tbl NVARCHAR(100), @rel NVARCHAR(200);

    BEGIN TRY
        PRINT '================================================';
        PRINT 'Cargando capa Bronze';
        PRINT '================================================';

        WHILE @ord <= 6
        BEGIN
            SELECT @tbl = tbl, @rel = rel_path FROM @files WHERE ord = @ord;

            SET @start_time = GETDATE();
            PRINT '>> Truncando: ' + @tbl;
            SET @sql = N'TRUNCATE TABLE ' + @tbl + N';';
            EXEC (@sql);

            PRINT '>> Insertando: ' + @tbl + '  <-  ' + @rel;
            SET @sql = N'BULK INSERT ' + @tbl + N' FROM ''' + @base_path + @rel + N'''
                WITH (
                    FIRSTROW        = 2,
                    FIELDTERMINATOR = '','',
                    ROWTERMINATOR   = ''0x0d0a'',
                    CODEPAGE        = ''65001'',
                    KEEPNULLS,
                    TABLOCK
                );';
            EXEC (@sql);

            SET @end_time = GETDATE();
            PRINT '>> Duración: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' s';
            PRINT '------------------------------------------------';
            SET @ord += 1;
        END;

        PRINT 'Bronze cargada. Duración total: '
              + CAST(DATEDIFF(SECOND, @batch_start, GETDATE()) AS NVARCHAR) + ' s';
    END TRY
    BEGIN CATCH
        PRINT '================================================';
        PRINT 'ERROR cargando la capa Bronze (tabla: ' + ISNULL(@tbl, '?') + ')';
        PRINT 'Mensaje: ' + ERROR_MESSAGE();
        PRINT 'Número : ' + CAST(ERROR_NUMBER() AS NVARCHAR);
        PRINT '================================================';
    END CATCH
END;
GO
