/*
===============================================================================
Script: init_database.sql
Propósito: Crea la base de datos 'DataWarehouse' y los tres esquemas de la
           arquitectura Medallion (bronze, silver, gold).
Ejecutar: PRIMERO, conectado a la base 'master'.
ADVERTENCIA: si la base 'DataWarehouse' ya existe, se ELIMINA y se vuelve a
             crear. Todos los datos que contenga se pierden.
===============================================================================
*/

USE master;
GO

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DataWarehouse')
BEGIN
    ALTER DATABASE DataWarehouse SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DataWarehouse;
END;
GO

CREATE DATABASE DataWarehouse;
GO

USE DataWarehouse;
GO

CREATE SCHEMA bronze;   -- Datos originales (sin procesar)
GO
CREATE SCHEMA silver;   -- Datos depurados y estandarizados
GO
CREATE SCHEMA gold;     -- Datos analíticos (vistas, modelo estrella)
GO
