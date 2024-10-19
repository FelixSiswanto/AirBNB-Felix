SELECT*FROM [dbo].[Main]
---FIND OCCUPANCY
SELECT
*,
365 - availability_365 AS Occupancy
FROM [dbo].[Available]

---FIND REVENUE = occupancy x price

SELECT
    *,
    ((365 - dbo.Available.availability_365) / 365) * dbo.Main.Price AS TotalRevenue
FROM dbo.Main
    LEFT JOIN dbo.Available 
        ON dbo.Available.id = dbo.Main.id

----------------------------------------------------------------------------------------Start Geospatial analysis

---FIND MOST SUCCESFUL AREA BY REVENUE

SELECT
    neighbourhood_cleansed,
    SUM(CAST(365 - dbo.Available.availability_365 AS BIGINT) * dbo.Main.Price) AS TotalRevenueArea
FROM dbo.Main
LEFT JOIN dbo.Available 
    ON dbo.Available.id = dbo.Main.id
GROUP BY neighbourhood_cleansed
ORDER BY TotalRevenueArea DESC;

----the revenue was really large, therefore i had to chaange the revenue data to bigint

---FIND daily AVERAGE REVENUE 

SELECT
    a.neighbourhood_cleansed,
    SUM(CAST(365 - b.availability_365 AS BIGINT) * a.price) / COUNT(DISTINCT a.id) AS AverageRevenueArea,
    SUM(365 - b.availability_365) / COUNT(DISTINCT a.id) AS AverageOccupancyArea,
    RANK() OVER (ORDER BY SUM(365 - b.availability_365)  / COUNT(DISTINCT a.id) DESC) AS OccupancyRank
FROM dbo.Main a
LEFT JOIN dbo.Available b 
    ON a.id = b.id
GROUP BY a.neighbourhood_cleansed
ORDER BY AverageRevenueArea DESC;


SELECT
    neighbourhood_cleansed,
    AverageRevenueArea,
	DailyRevenueArea,
    AverageOccupancyArea,
    RANK() OVER (ORDER BY AverageOccupancyArea DESC) AS OccupancyRank
FROM (
    SELECT
        a.neighbourhood_cleansed,
        SUM(CAST(365 - b.availability_365 AS BIGINT) * a.price) / COUNT(DISTINCT a.id) AS AverageRevenueArea,
		SUM(CAST(365 - b.availability_365 AS BIGINT) * a.price) / (365*COUNT(DISTINCT a.id)) AS DailyRevenueArea,
        SUM(365 - b.availability_365) / COUNT(DISTINCT a.id) AS AverageOccupancyArea
    FROM dbo.Main a
    LEFT JOIN dbo.Available b 
        ON a.id = b.id
    GROUP BY a.neighbourhood_cleansed
) AS Subquery
ORDER BY AverageRevenueArea DESC;
--- Here we can see that occupancy does not always equate to high  DailyRevenueArea per place. Hinohara Mura has one of the lowest average occupancy in a year, but given that it is a vacation spot
-- I want to only focus on the top 15 best performing areas. 

SELECT TOP 15
    neighbourhood_cleansed,
    AverageRevenueArea,
    DailyRevenueArea,
    AverageOccupancyArea,
    RANK() OVER (ORDER BY AverageRevenueArea DESC) AS RevenueRank
INTO TargetRegion
FROM (
    SELECT
        a.neighbourhood_cleansed,
        SUM(CAST(365 - b.availability_365 AS BIGINT) * a.price) / COUNT(DISTINCT a.id) AS AverageRevenueArea,
        SUM(CAST(365 - b.availability_365 AS BIGINT) * a.price) / (365 * COUNT(DISTINCT a.id)) AS DailyRevenueArea,
        SUM(365 - b.availability_365) / COUNT(DISTINCT a.id) AS AverageOccupancyArea
    FROM dbo.Main a
    LEFT JOIN dbo.Available b 
        ON a.id = b.id
    GROUP BY a.neighbourhood_cleansed
) AS Subquery
ORDER BY AverageRevenueArea DESC;
	
SELECT*FROM [dbo].[TargetRegion]

------------------------------------------------- We will only analyze our target area based on these regions from now. 

----------------------------------------------------------------------------START ROOM ANALYSIS------------------------------------------------------


--- First find the target region
SELECT
*
FROM [dbo].[Main]
	INNER JOIN TargetRegion
		ON TargetRegion.neighbourhood_cleansed = [dbo].[Main].neighbourhood_cleansed

----- Next we find average revenue from property type per area 
SELECT 
    [dbo].[Main].neighbourhood_cleansed AS Area,
    [dbo].[Main].room_type AS RoomType,
    AVG((CAST(365 - dbo.Available.availability_365 AS bigint) * dbo.Main.Price) / 365.0) AS AverageRevenue

FROM 
    [dbo].[Main]
    INNER JOIN TargetRegion
        ON TargetRegion.neighbourhood_cleansed = [dbo].[Main].neighbourhood_cleansed
    INNER JOIN dbo.Available
        ON dbo.Available.id = dbo.Main.id

GROUP BY 
    [dbo].[Main].neighbourhood_cleansed, 
    [dbo].[Main].room_type
ORDER BY 
    Area;

--- Because the data is getting segmented a lot more, I am becoming more worried over the potential outliers which drags our data, therefore I Complement it with median price for more accurate result.
--- 
--- I first use CTE instead of another subquery so that what I am doing here is clearer.
WITH PriceStats AS (
    SELECT 
        neighbourhood_cleansed AS Area,
        room_type AS RoomType,
        Price,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Price) 
        OVER (PARTITION BY neighbourhood_cleansed, room_type) AS MedianPrice
    FROM dbo.Main
)

SELECT 
    ps.Area,
    ps.RoomType,
    AVG((CAST(365 - a.availability_365 AS bigint) * m.Price) / 365.0) AS AverageRevenue,
    AVG(ps.MedianPrice * ((365 - a.availability_365) / 365.0)) AS AverageRevenueByMedianPrice
FROM 
    PriceStats ps
    INNER JOIN dbo.Main m
        ON ps.Area = m.neighbourhood_cleansed 
        AND ps.RoomType = m.room_type
    INNER JOIN TargetRegion tr
        ON tr.neighbourhood_cleansed = ps.Area
    INNER JOIN dbo.Available a
        ON a.id = m.id
GROUP BY 
    ps.Area, 
    ps.RoomType
ORDER BY 
    ps.Area;


	WITH PriceStats AS (
    SELECT 
        neighbourhood_cleansed AS Area,
        room_type AS RoomType,
        Price,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Price) 
            OVER (PARTITION BY neighbourhood_cleansed, room_type) AS MedianPrice
    FROM dbo.Main
)

-- Create a temporary table from the CTE
SELECT 
    ps.Area,
    ps.RoomType,
    AVG((CAST(365 - a.availability_365 AS bigint) * m.Price) / 365.0) AS AverageRevenue,
    AVG(ps.MedianPrice * ((365 - a.availability_365) / 365.0)) AS AverageRevenueByMedianPrice
INTO #TempPriceStats
FROM 
    PriceStats ps
    INNER JOIN dbo.Main m
        ON ps.Area = m.neighbourhood_cleansed 
        AND ps.RoomType = m.room_type
    INNER JOIN TargetRegion tr
        ON tr.neighbourhood_cleansed = ps.Area
    INNER JOIN dbo.Available a
        ON a.id = m.id
GROUP BY 
    ps.Area, 
    ps.RoomType
ORDER BY 
    ps.Area;




--- Find the top performing room type per area
--- Now we have the choice to invest, but which one? I want to find which room type is most appropriate per area. 


SELECT *
FROM #TempPriceStats tps
WHERE tps.AverageRevenueByMedianPrice = (
    SELECT MAX(AverageRevenueByMedianPrice) 
    FROM #TempPriceStats 
    WHERE Area = tps.Area
)
ORDER BY tps.AverageRevenueByMedianPrice DESC

-----FINALLY I want that one! what types of things should I have inside? Now this is where outside consideration and research matters, it is not surprising that popular areas such as Chiyoda and Shibuya area really popular, but what is hinohara? This is a vacation place and if you remember the previous table, the occupancy rate here is rather low. The issue that arises from this low occupancy is that we are faced with greater risk if occupancy suddenly declines. 
--Stable cash flow: A high occupancy rate indicates demand, providing consistent revenue.
--Lower volatility: Demand-driven properties tend to have less price fluctuation.

--- Further qeustions that we can ask. Assuming that we have chosen an area and know the exact roomtype. What should the room consist of?
--- Assume that we have decided to open an airbnb in Shibuya Ku, lets analyze

SELECT
  
	dbo.Main.id,
	dbo.Main.accommodates,
	dbo.Main.bathrooms,
	dbo.Main.bedrooms,
	dbo.Main.beds,
	price,
    ((365 - dbo.Available.availability_365) / 365) * dbo.Main.Price AS TotalRevenue
INTO #Shibuyadata
FROM dbo.Main
    LEFT JOIN dbo.Available 
        ON dbo.Available.id = dbo.Main.id
WHERE neighbourhood_cleansed = 'Shibuya Ku' and room_type = 'Entire home/apt'


SELECT
COUNT(CASE WHEN accommodates > 7 THEN id ELSE NULL END) AS "Big_capacity",
COUNT(CASE WHEN accommodates < 7 AND accommodates > 2  THEN id ELSE NULL END) AS "Mid_capacity",
COUNT(CASE WHEN accommodates <= 2 THEN id ELSE NULL END) AS "Small_capacity"
FROM #Shibuyadata


SELECT
  
	dbo.Main.id,
	dbo.Main.accommodates,
	dbo.Main.bathrooms,
	dbo.Main.bedrooms,
	dbo.Main.beds,
	price,
    ((365 - dbo.Available.availability_365) / 365) * dbo.Main.Price AS TotalRevenue

FROM dbo.Main
    LEFT JOIN dbo.Available 
        ON dbo.Available.id = dbo.Main.id
WHERE neighbourhood_cleansed = 'Shibuya Ku' and room_type = 'Entire home/apt' and accommodates < 7 AND accommodates > 2