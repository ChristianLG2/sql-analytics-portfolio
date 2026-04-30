# Project 03 Query Optimization
### T-SQL · Execution Plans · Index Analysis · SQL Server 2022

Query performance analysis on two analytical queries from the Northwind database. Each case documents baseline execution statistics, execution plan operators, optimization attempts, and findings; including cases where the query optimizer made better decisions than manual intervention.

---

## Business Questions

> 1. Can the supplier revenue ranking query be made more efficient through indexing?
> 2. Why is the monthly sales trends query already optimal, and what keeps it that way?

---

## Environment

```
Database:    Northwind (SQL Server 2022)
Tool:        SSMS 20
Diagnostics: SET STATISTICS IO ON / SET STATISTICS TIME ON
             SET STATISTICS PROFILE ON
             Graphical execution plan (.sqlplan)
```

---

## Case 1 Supplier Revenue Ranking

### Query Profile

3-CTE architecture joining Suppliers → Products → Order Details → Categories,
computing total revenue and discount per supplier per category, then applying
`RANK() OVER (ORDER BY)` and `RANK() OVER (PARTITION BY CategoryName)` window functions.

### Baseline Statistics

```
Table           Logical Reads    Notes
─────────────────────────────────────────────
Products             4,310       ← bottleneck
Order Details           15       efficient
Suppliers                2       efficient
Categories               2       efficient
─────────────────────────────────────────────
Total                4,329       76ms elapsed
```
![Supplier-Revenue-Ranking-Query](outputs/stats/01_Before_Supplier_Ranking_stats.png)

### Execution Plan Operators

```
[Clustered Index Scan] — Products (full scan, 4,310 reads)
        ↓
[Nested Loop] — Products outer → Order Details inner
        ↓
[Hash Match #1] — JOIN Categories
        ↓
[Hash Match #2] — JOIN Suppliers
        ↓
[Hash Match #3] — GROUP BY aggregation
        ↓
[Sort + Window Aggregate] — RANK() computation
        ↓
Result (49 rows)
```
![Supplier-Revenue-Ranking-EP](outputs/queryplans/01_Supplier_Ranking_QPlan.png)

**Root cause:** SQL Server performs a Clustered Index Scan on Products as the outer side of a Nested Loop join with Order Details — reading Products once per Order Detail row lookup, producing 4,310 logical reads.

### Optimization Attempt — Covering Index

```sql
CREATE INDEX IX_Products_SupplierID_Covering
ON Products (SupplierID)
INCLUDE (ProductID, CategoryID);
```

**Hypothesis:** Including `ProductID` and `CategoryID` in the index eliminates key lookups back to the clustered index, reducing Products reads significantly.

### Results After Forced Index Hint

```sql
JOIN Products p WITH (INDEX(IX_Products_SupplierID_Covering))
    ON s.SupplierID = p.SupplierID
```

```
Table           Before          After           Delta
──────────────────────────────────────────────────────────
Products         4,310              2            -99.95% ✅
Order Details       15          4,473         +29,720%  ❌
Suppliers            2            154          +7,600%  ❌
Categories           2            154          +7,600%  ❌
──────────────────────────────────────────────────────────
Total            4,329          4,631              +302  ❌ worse
Elapsed             76ms           80ms            +4ms  ❌ slower
```

### Finding

> The covering index reduced Products reads by 99.95% — but forcing it caused
> SQL Server to switch from a Hash Match join strategy to a Nested Loop on
> Order Details, Suppliers, and Categories. The optimizer shifted cost from
> one table to three others, increasing total logical reads by 302 and elapsed
> time by 4ms.
>
> **The query optimizer was correct to ignore the index.** On a small dataset
> like Northwind, the original Hash Match plan — reading Products once via a
> Clustered Index Scan — is more efficient than 77 nested loop iterations
> through Order Details. This demonstrates that index hints should be applied
> with caution on small tables: the optimizer has visibility into the full
> execution cost that per-table analysis does not.

### Key Lesson

```
Fixing one bottleneck in isolation can shift cost rather than reduce it. The optimizer sees total query cost. Manual index hints see one table. Always measure total reads, not just the table being targeted.
```

---

## Case 2 — Monthly Sales Trends

### Query Profile

Single CTE computing monthly revenue from Orders × Order Details using
`DATEFROMPARTS()` for month bucketing, then applying four window functions:
`LAG()` for prior month revenue, derived MoM growth percentage, and
`AVG() OVER (ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)` for rolling average.

### Baseline Statistics

```
Table           Logical Reads    Notes
─────────────────────────────────────────────
Orders                  24       efficient
Order Details           15       efficient
Worktable                0       window functions
                                 running in memory
─────────────────────────────────────────────
Total                   39       50ms elapsed
```

### Execution Plan Operators

```
[Clustered Index Scan] Orders (830 rows, ordered forward)
        ↓
[Compute Scalar] DATEFROMPARTS() month bucketing
        ↓
[Clustered Index Scan] Order Details (2,155 rows, ordered forward)
        ↓
[Compute Scalar] revenue calculation (UnitPrice × Quantity × (1-Discount))
        ↓
[Merge Join] Orders ⋈ Order Details on OrderID
        ↓
[Sort] — ORDER BY SaleMonth
        ↓
[Stream Aggregate] GROUP BY month → SUM(revenue)
        ↓
[Window Spool × 2] rolling average (ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
                      LAG() computation
        ↓
[Compute Scalar × 4] ROUND(), MoM growth formula, NULLIF division guard
        ↓
Result (23 rows)
```

### Why This Query Is Already Optimal

**Merge Join instead of Hash Match or Nested Loop:**

SQL Server chose a Merge Join on `OrderID` — the most efficient join typewhen both inputs are pre-sorted on the join key. Orders and Order Detailsare both clustered on `OrderID`, so no additional sort is required for the join.
Total join cost: near zero.

**Ordered Forward scans:**

Both Clustered Index Scans are `ORDERED FORWARD` — SQL Server reads each tableonce in primary key order, feeds the Merge Join directly, and avoids any random I/O. This is why Orders costs only 24 reads and Order Details only 15.

**Window Spool in memory:**

The `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW` rolling average and `LAG()`
computation both use Window Spool operators with zero worktable disk spills the entire window frame fits in memory. On larger datasets this would spill to `tempdb`, significantly increasing I/O.

**Existing OrderDate index:**

```
OrderDate    NONCLUSTERED    OrderDate
```

The `WHERE o.OrderDate IS NOT NULL` filter uses this index to eliminate null
rows before the scan keeping the Orders read count at 24 rather than 830.

### Index Analysis Orders

```
Index               Type            Column          Role
────────────────────────────────────────────────────────────────
PK_Orders           CLUSTERED       OrderID         Merge Join
OrderDate           NONCLUSTERED    OrderDate       NULL filter
CustomerID          NONCLUSTERED    CustomerID      Not used
EmployeeID          NONCLUSTERED    EmployeeID      Not used
ShippedDate         NONCLUSTERED    ShippedDate     Not used
ShipPostalCode      NONCLUSTERED    ShipPostalCode  Not used
```

The existing index coverage on Orders is comprehensive. No additional indexes are needed for this query pattern.

### Finding

> The monthly sales trends query achieves 39 total logical reads and 50ms
> elapsed time through three naturally aligned conditions: both tables are
> clustered on `OrderID` enabling a zero-cost Merge Join, an existing
> `OrderDate` index eliminates null rows before scanning, and the window
> function frame is small enough to execute entirely in memory.
>
> **No optimization is needed or advisable.** Introducing indexes or hints
> would add maintenance overhead without measurable performance benefit at
> this data volume.

### Scale Consideration

At production scale (millions of orders) this query would benefit from:

```sql
-- Partitioned index on OrderDate for range scans
CREATE INDEX IX_Orders_OrderDate_Covering
ON Orders (OrderDate)
INCLUDE (OrderID);

-- Materialized monthly aggregation to avoid
-- recomputing window functions on every query
```

At Northwind scale — unnecessary. Documenting for production awareness.

---

## Summary Comparison

| Metric | Supplier Ranking | Sales Trends |
|---|---|---|
| Total logical reads | 4,329 | 39 |
| Elapsed time | 76ms | 50ms |
| Primary join type | Hash Match + Nested Loop | Merge Join |
| Bottleneck | Products 4,310 reads | None |
| Index added | IX_Products_SupplierID_Covering | None needed |
| Optimization result | Optimizer ignored index correct | Already optimal |
| Key lesson | Index hints shift cost, not always reduce it | Pre-sorted clustered indexes enable zero-cost joins |

---

## Key T-SQL Concepts Demonstrated

```
SET STATISTICS IO ON     → measures logical reads per table
SET STATISTICS TIME ON   → measures CPU and elapsed time
SET STATISTICS PROFILE ON → shows full operator-level execution plan
Clustered Index Scan     → full table read in key order
Merge Join               → optimal join when both inputs pre-sorted
Hash Match               → optimal join for unsorted medium datasets
Nested Loop              → optimal when outer set is small
Window Spool             → in-memory frame computation for OVER() clauses
Covering Index           → INCLUDE columns eliminate key lookups
Index Hint               → WITH (INDEX()) forces optimizer choice
```

---

## Files

```
03_query_optimization/
├── sql/
│   ├── 01_supplier_ranking_baseline.sql
│   ├── 02_supplier_ranking_optimized.sql
│   ├── 03_sales_trends_baseline.sql
│   └── 04_index_analysis.sql
├── execution_plans/
│   ├── supplier_ranking_before.sqlplan
│   ├── supplier_ranking_after.sqlplan
│   └── sales_trends.sqlplan
├── outputs/
│   └── optimization_summary.png
└── README.md
```

---

## Part of the SQL Analytics Portfolio

[![SQL Portfolio](https://img.shields.io/badge/SQL-Analytics%20Portfolio-1F4E79?style=flat)](https://github.com/ChristianLG2/SQL-Analytics-Portfolio)
[![Christian Lira](https://img.shields.io/badge/Built%20by-Christian%20Lira-2E74B5?style=flat)](https://clirago.com)