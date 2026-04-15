USE Northwind;
GO

-- Business question: Are orders being shipped on time?
-- Which shippers have the longest delays? Which employees handle the most volume?

-- Concepts demonstrated:
--   DATEDIFF(DAY, ...) for fulfillment days calculation
--   AVG() OVER (PARTITION BY) for per-shipper averages
--   CASE WHEN for on-time classification
--   SUM(CASE WHEN ...) as T-SQL equivalent of COUNT(*) FILTER (WHERE ...)
--   NULL handling with WHERE ShippedDate IS NOT NULL

WITH ShipperDetails AS (
	SELECT 
		s.ShipperID, 
		s.CompanyName,
		COUNT(DISTINCT o.OrderID) AS OrderCount,
		ROUND(AVG(CAST(DATEDIFF(DAY, o.OrderDate, o.ShippedDate) AS FLOAT)),1) AS AvgDaysToShip,
		SUM(CASE WHEN o.ShippedDate <= RequiredDate THEN 1 ELSE 0 END) AS OnTimeOrders,
		ROUND(100 * SUM(CASE WHEN o.ShippedDate <= o.RequiredDate THEN 1 ELSE 0 END) /NULLIF(COUNT(o.OrderID),0),2) AS OnTimePct,
		ROUND(100 * SUM(CASE WHEN o.ShippedDate > RequiredDate THEN 1 ELSE 0 END) /NULLIF(COUNT(o.OrderID),0),2) AS LatePct,
		AVG(o.Freight) AS AvgFreightExp,
		SUM(o.Freight) AS TotalSpentPerShipper
	FROM Shippers AS s
	JOIN Orders AS o
		ON s.ShipperID = o.ShipVia
	GROUP BY s.ShipperID, s.CompanyName
)
SELECT *
FROM ShipperDetails
ORDER BY AvgDaysToShip