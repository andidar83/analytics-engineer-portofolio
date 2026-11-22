-- Supports findings: the discount / margin / cancellation pattern follows the salesperson, not the customer.
-- One row per salesperson and customer.

select
    s.salesperson_name
    , c.customer_name
    , c.city
    , count(distinct f.order_id) filter (where f.is_valid_sale)      as valid_orders
    , count(distinct f.order_id) filter (where not f.is_valid_sale)  as cancelled_orders
    , sum(f.revenue_idr) filter (where f.is_valid_sale)              as revenue_idr
    , round(100.0 * sum(f.discount_amount_idr) filter (where f.is_valid_sale)
          / nullif(sum(f.gross_amount_idr) filter (where f.is_valid_sale), 0), 1) as discount_pct
    , round(100.0 * sum(f.gross_margin_idr) filter (where f.is_valid_sale)
          / nullif(sum(f.revenue_idr) filter (where f.is_valid_sale), 0), 1)      as margin_pct
from {{ ref('fact_order_lines') }} f
join {{ ref('dim_salesperson') }} s on s.salesperson_id = f.salesperson_id
join {{ ref('dim_customer') }} c    on c.customer_id = f.customer_id
group by 1, 2, 3
order by 1, revenue_idr desc nulls last