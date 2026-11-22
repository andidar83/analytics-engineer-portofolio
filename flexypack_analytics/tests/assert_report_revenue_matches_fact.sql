-- The report's total revenue must equal the total revenue of confirmed orders in the fact table.
-- Returns a row (= test fails) if the two differ by more than 1 IDR.

with report as (
    select sum(revenue_idr) as report_revenue
    from {{ ref('rpt_salesperson_performance') }}
),

fact as (
    select sum(revenue_idr) as fact_revenue
    from {{ ref('fact_order_lines') }}
    where is_valid_sale
)

select report.report_revenue, fact.fact_revenue
from report
cross join fact
where abs(report.report_revenue - fact.fact_revenue) > 1