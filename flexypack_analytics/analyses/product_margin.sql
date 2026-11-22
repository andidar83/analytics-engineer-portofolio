-- Supports findings: margin per product at list price vs actually realised, after discount.
-- Shows which products are most and least profitable, and that list-price margins sit around 33-36%.

select
    p.category_name
    , p.product_name
    , p.list_price_idr
    , p.standard_price_idr                                                         as unit_cost_idr
    , round(100.0 * (p.list_price_idr - p.standard_price_idr) / p.list_price_idr, 1) as margin_at_list_price_pct
    , count(*)                                                                     as lines
    , sum(f.revenue_idr)                                                           as revenue_idr
    , round(100.0 * sum(f.discount_amount_idr) / nullif(sum(f.gross_amount_idr), 0), 1) as discount_pct
    , round(100.0 * sum(f.gross_margin_idr) / nullif(sum(f.revenue_idr), 0), 1)         as actual_margin_pct
from {{ ref('fact_order_lines') }} f
join {{ ref('dim_product') }} p on p.product_id = f.product_id
where f.is_valid_sale
group by 1, 2, 3, 4
order by actual_margin_pct