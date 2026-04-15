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


WITH ShippingDetails AS (
	SELECT 
		s.ShipperID, 
		s.CompanyName,
		o.OrderID,
		o.OrderDate,
		o.RequiredDate,
		o.ShippedDate,
		DATEDIFF(DAY, o.RequiredDate, o.ShippedDate) AS DaysLate
	FROM Shippers AS s
	JOIN Orders AS o
		ON s.ShipperID = o.ShipVia
	WHERE o.ShippedDate > o.RequiredDate
)
SELECT *
FROM ShippingDetails
ORDER BY DaysLate DESC;
