-- Supports findings: on every product, Irfan & Joko discount ~35% and earn ~0% margin, while the rest of the team
-- discounts 5-9% and earns 21-33% on the same product. So the product is not the cause.
-- Names are hard-coded on purpose: this is a one-off investigation, not a reusable report.

select
    p.product_name
    , case when s.salesperson_name in ('Irfan Hakim', 'Joko Setiawan')
           then 'Irfan & Joko' else 'Rest of team' end                                  as grp
    , count(*)                                                                         as lines
    , round(100.0 * sum(f.discount_amount_idr) / nullif(sum(f.gross_amount_idr), 0), 1) as discount_pct
    , round(100.0 * sum(f.gross_margin_idr) / nullif(sum(f.revenue_idr), 0), 1)         as margin_pct
from {{ ref('fact_order_lines') }} f
join {{ ref('dim_product') }} p     on p.product_id = f.product_id
join {{ ref('dim_salesperson') }} s on s.salesperson_id = f.salesperson_id
where f.is_valid_sale
group by 1, 2
order by 1, 2