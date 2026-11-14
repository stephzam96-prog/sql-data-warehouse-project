# Requisitos del proyecto

**Proyecto:** Data Warehouse con arquitectura Medallion en SQL Server (ISW623)

## Objetivo
Desarrollar un almacén de datos moderno en SQL Server que consolide la información de ventas, permita generar reportes analíticos y facilite la toma de decisiones.

## Especificaciones
- **Fuentes de datos:** importar información de dos sistemas (ERP y CRM) desde archivos CSV.
- **Calidad de los datos:** limpiar y resolver los problemas de calidad antes del análisis.
- **Integración:** combinar ambas fuentes en un único modelo de datos fácil de usar para consultas analíticas.
- **Alcance:** solo el conjunto de datos más reciente, sin historial.
- **Documentación:** documentar el modelo de datos para el negocio y los equipos de análisis.

## Orígenes de datos
| Sistema | Archivo | Contenido |
|---|---|---|
| CRM | cust_info.csv | Clientes |
| CRM | prd_info.csv | Productos |
| CRM | sales_details.csv | Ventas y pedidos |
| ERP | CUST_AZ12.csv | Fecha de nacimiento y género del cliente |
| ERP | LOC_A101.csv | País del cliente |
| ERP | PX_CAT_G1V2.csv | Categorías de productos |

## Capas
| Capa | Contenido | Objetos | Carga |
|---|---|---|---|
| Bronze | Datos originales, sin transformar | Tablas | Truncate & Insert |
| Silver | Datos limpios y estandarizados | Tablas | Truncate & Insert |
| Gold | Datos listos para análisis (modelo estrella) | Vistas | No aplica |

## Diagramas
- `erd_origenes.png`: tablas de origen (CRM y ERP) y sus relaciones.
- `flujo_datos.png`: recorrido de los datos por Bronze, Silver y Gold.
- `modelo_estrella_gold.png`: modelo de datos final (esquema en estrella).
