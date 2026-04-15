WITH ShipperDetails AS (
	SELECT 
		s.ShipperID, 
		s.CompanyName,
		COUNT(DISTINCT o.OrderID) AS OrderCount,
		ROUND(AVG(CAST(DATEDIFF(DAY, o.OrderDate, o.ShippedDate) AS FLOAT)),1) AS AvgDaysToShip,
		SUM(CASE WHEN o.ShippedDate <= RequiredDate THEN 1 ELSE 0 END) AS OnTimeOrders,
		ROUND(100 * SUM(CASE WHEN o.ShippedDate <= o.RequiredDate THEN 1 ELSE 0 END) /NULLIF(COUNT(o.OrderID),0),2) AS OnTimePct
	FROM Shippers AS s
	JOIN Orders AS o
		ON s.ShipperID = o.ShipVia
	GROUP BY ShipperID, CompanyName
)
SELECT *
FROM ShipperDetails
ORDER BY AvgDaysToShip