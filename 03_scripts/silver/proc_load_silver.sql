/*
===============================================================================
Stored Procedure: silver.load_silver
Propósito: Limpia/estandariza los datos de Bronze y los carga en Silver
           (Truncate & Insert). No recibe parámetros.
Uso: EXEC silver.load_silver;
Problemas de calidad detectados en los CSV y cómo se resuelven aquí:
  crm_cust_info : ids duplicados (se queda el registro más reciente), filas
                  basura sin cst_key, espacios sobrantes, códigos M/S/F.
  crm_prd_info  : prd_key mezcla categoría + clave de producto, costos nulos,
                  prd_end_dt anterior a prd_start_dt (se recalcula con LEAD),
                  códigos de línea (R, M, S, T).
  crm_sales     : fechas 0 o mal formadas, sales/price nulos o <= 0 o que no
                  cumplen sales = quantity * price.
  erp_cust_az12 : prefijo 'NAS' en cid, fechas de nacimiento futuras,
                  género con variantes (M, F, Male, Female, vacío).
  erp_loc_a101  : guiones en cid, países con códigos (DE, US, USA) y vacíos.
===============================================================================
*/

USE DataWarehouse;
GO

CREATE OR ALTER PROCEDURE silver.load_silver
AS
BEGIN
    DECLARE @start_time DATETIME, @batch_start DATETIME = GETDATE();

    BEGIN TRY
        PRINT '================================================';
        PRINT 'Cargando capa Silver';
        PRINT '================================================';

        ------------------------------------------------------------------ CRM
        SET @start_time = GETDATE();
        PRINT '>> silver.crm_cust_info';
        TRUNCATE TABLE silver.crm_cust_info;
        INSERT INTO silver.crm_cust_info
            (cst_id, cst_key, cst_firstname, cst_lastname,
             cst_marital_status, cst_gndr, cst_create_date)
        SELECT
            cst_id, cst_key,
            TRIM(cst_firstname),
            TRIM(cst_lastname),
            CASE UPPER(TRIM(cst_marital_status))
                 WHEN 'S' THEN 'Single'
                 WHEN 'M' THEN 'Married'
                 ELSE 'n/a' END,
            CASE UPPER(TRIM(cst_gndr))
                 WHEN 'F' THEN 'Female'
                 WHEN 'M' THEN 'Male'
                 ELSE 'n/a' END,
            cst_create_date
        FROM (
            SELECT
                TRY_CAST(TRIM(cst_id) AS INT) AS cst_id,
                TRIM(cst_key) AS cst_key,
                cst_firstname, cst_lastname, cst_marital_status, cst_gndr,
                cst_create_date,
                ROW_NUMBER() OVER (
                    PARTITION BY TRY_CAST(TRIM(cst_id) AS INT)
                    ORDER BY cst_create_date DESC) AS flag_last
            FROM bronze.crm_cust_info
            WHERE TRY_CAST(TRIM(cst_id) AS INT) IS NOT NULL
              AND LEN(TRIM(ISNULL(cst_key, ''))) > 0
        ) t
        WHERE flag_last = 1;
        PRINT '   Duración: ' + CAST(DATEDIFF(SECOND, @start_time, GETDATE()) AS NVARCHAR) + ' s';

        SET @start_time = GETDATE();
        PRINT '>> silver.crm_prd_info';
        TRUNCATE TABLE silver.crm_prd_info;
        INSERT INTO silver.crm_prd_info
            (prd_id, cat_id, prd_key, prd_nm, prd_cost, prd_line,
             prd_start_dt, prd_end_dt)
        SELECT
            prd_id,
            REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_'),        -- categoría
            SUBSTRING(prd_key, 7, LEN(prd_key)),                -- clave de producto
            TRIM(prd_nm),
            ISNULL(prd_cost, 0),
            CASE UPPER(TRIM(prd_line))
                 WHEN 'M' THEN 'Mountain'
                 WHEN 'R' THEN 'Road'
                 WHEN 'S' THEN 'Other Sales'
                 WHEN 'T' THEN 'Touring'
                 ELSE 'n/a' END,
            prd_start_dt,
            -- fin de vigencia = día anterior al inicio de la siguiente versión
            DATEADD(DAY, -1,
                LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt))
        FROM bronze.crm_prd_info;
        PRINT '   Duración: ' + CAST(DATEDIFF(SECOND, @start_time, GETDATE()) AS NVARCHAR) + ' s';

        SET @start_time = GETDATE();
        PRINT '>> silver.crm_sales_details';
        TRUNCATE TABLE silver.crm_sales_details;
        INSERT INTO silver.crm_sales_details
            (sls_ord_num, sls_prd_key, sls_cust_id, sls_order_dt, sls_ship_dt,
             sls_due_dt, sls_sales, sls_quantity, sls_price)
        SELECT
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            CASE WHEN sls_order_dt IS NULL OR sls_order_dt = 0 OR LEN(sls_order_dt) <> 8
                 THEN NULL ELSE TRY_CAST(CAST(sls_order_dt AS VARCHAR(8)) AS DATE) END,
            CASE WHEN sls_ship_dt IS NULL OR sls_ship_dt = 0 OR LEN(sls_ship_dt) <> 8
                 THEN NULL ELSE TRY_CAST(CAST(sls_ship_dt AS VARCHAR(8)) AS DATE) END,
            CASE WHEN sls_due_dt IS NULL OR sls_due_dt = 0 OR LEN(sls_due_dt) <> 8
                 THEN NULL ELSE TRY_CAST(CAST(sls_due_dt AS VARCHAR(8)) AS DATE) END,
            -- ventas: si es nula, <= 0 o no coincide, se recalcula
            CASE WHEN sls_sales IS NULL OR sls_sales <= 0
                      OR sls_sales <> sls_quantity * ABS(sls_price)
                 THEN sls_quantity * ABS(sls_price)
                 ELSE sls_sales END,
            sls_quantity,
            -- precio: si es nulo o <= 0 se deriva de ventas / cantidad
            CASE WHEN sls_price IS NULL OR sls_price <= 0
                 THEN sls_sales / NULLIF(sls_quantity, 0)
                 ELSE sls_price END
        FROM bronze.crm_sales_details;
        PRINT '   Duración: ' + CAST(DATEDIFF(SECOND, @start_time, GETDATE()) AS NVARCHAR) + ' s';

        ------------------------------------------------------------------ ERP
        SET @start_time = GETDATE();
        PRINT '>> silver.erp_cust_az12';
        TRUNCATE TABLE silver.erp_cust_az12;
        INSERT INTO silver.erp_cust_az12 (cid, bdate, gen)
        SELECT
            CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid)) ELSE cid END,
            CASE WHEN bdate > CAST(GETDATE() AS DATE) THEN NULL ELSE bdate END,
            CASE WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
                 WHEN UPPER(TRIM(gen)) IN ('M', 'MALE')   THEN 'Male'
                 ELSE 'n/a' END
        FROM bronze.erp_cust_az12;
        PRINT '   Duración: ' + CAST(DATEDIFF(SECOND, @start_time, GETDATE()) AS NVARCHAR) + ' s';

        SET @start_time = GETDATE();
        PRINT '>> silver.erp_loc_a101';
        TRUNCATE TABLE silver.erp_loc_a101;
        INSERT INTO silver.erp_loc_a101 (cid, cntry)
        SELECT
            REPLACE(cid, '-', ''),
            CASE WHEN TRIM(ISNULL(cntry, '')) = ''             THEN 'n/a'
                 WHEN UPPER(TRIM(cntry)) = 'DE'                THEN 'Germany'
                 WHEN UPPER(TRIM(cntry)) IN ('US', 'USA')      THEN 'United States'
                 ELSE TRIM(cntry) END
        FROM bronze.erp_loc_a101;
        PRINT '   Duración: ' + CAST(DATEDIFF(SECOND, @start_time, GETDATE()) AS NVARCHAR) + ' s';

        SET @start_time = GETDATE();
        PRINT '>> silver.erp_px_cat_g1v2';
        TRUNCATE TABLE silver.erp_px_cat_g1v2;
        INSERT INTO silver.erp_px_cat_g1v2 (id, cat, subcat, maintenance)
        SELECT TRIM(id), TRIM(cat), TRIM(subcat), TRIM(maintenance)
        FROM bronze.erp_px_cat_g1v2;
        PRINT '   Duración: ' + CAST(DATEDIFF(SECOND, @start_time, GETDATE()) AS NVARCHAR) + ' s';

        PRINT 'Silver cargada. Duración total: '
              + CAST(DATEDIFF(SECOND, @batch_start, GETDATE()) AS NVARCHAR) + ' s';
    END TRY
    BEGIN CATCH
        PRINT '================================================';
        PRINT 'ERROR cargando la capa Silver';
        PRINT 'Mensaje: ' + ERROR_MESSAGE();
        PRINT 'Número : ' + CAST(ERROR_NUMBER() AS NVARCHAR);
        PRINT '================================================';
    END CATCH
END;
GO
