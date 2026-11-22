with base as (
    select
        fo.order_line_id
        , fo.order_id
        , fo.salesperson_id
        , fo.customer_id
        , fo.product_category_id
        , fo.is_valid_sale
        , fo.gross_amount_idr
        , fo.discount_amount_idr
        , fo.revenue_idr
        , fo.cost_idr
        , fo.gross_margin_idr
        , c.city as customer_city
    from {{ ref('fact_order_lines') }} fo
    left join {{ ref('dim_customer') }} c on c.customer_id = fo.customer_id
),

per_salesperson as (
    select
        salesperson_id

        -- valid sales only
        , sum(revenue_idr)                    filter (where is_valid_sale)     as revenue_idr
        , sum(gross_margin_idr)               filter (where is_valid_sale)     as gross_margin_idr
        , sum(discount_amount_idr)            filter (where is_valid_sale)     as discount_amount_idr
        , sum(gross_amount_idr)               filter (where is_valid_sale)     as gross_amount_idr
        , sum(cost_idr)                       filter (where is_valid_sale)     as cost_idr
        , count(distinct order_id)            filter (where is_valid_sale)     as orders
        , count(distinct product_category_id) filter (where is_valid_sale)     as categories_sold
        , count(distinct customer_id)         filter (where is_valid_sale)     as customers
        , count(distinct customer_city)       filter (where is_valid_sale)     as customer_cities

        -- cancelled orders
        , count(distinct order_id)            filter (where not is_valid_sale) as cancelled_orders
        , sum(revenue_idr)                    filter (where not is_valid_sale) as cancelled_value_idr
        , count(distinct order_id)                                             as all_orders
    from base
    group by salesperson_id
)

select
    s.salesperson_id
    , s.salesperson_name
    , coalesce(p.revenue_idr, 0)                                                         as revenue_idr
    , round(coalesce(p.gross_margin_idr, 0), 0)                                          as gross_margin_idr
    , round(100.0 * p.gross_margin_idr / nullif(p.revenue_idr, 0), 1)                    as gross_margin_pct
    , round(100.0 * (p.gross_amount_idr - p.cost_idr) / nullif(p.gross_amount_idr, 0), 1) as margin_before_discount_pct
    , round(100.0 * p.discount_amount_idr / nullif(p.gross_amount_idr, 0), 1)            as avg_discount_pct
    , coalesce(p.orders, 0)                                                              as orders
    , round(p.revenue_idr / nullif(p.orders, 0), 0)                                      as avg_order_value_idr
    , coalesce(p.categories_sold, 0)                                                     as categories_sold
    , coalesce(p.customers, 0)                                                           as customers
    , coalesce(p.customer_cities, 0)                                                     as customer_cities
    , coalesce(p.cancelled_orders, 0)                                                    as cancelled_orders
    , coalesce(p.cancelled_value_idr, 0)                                                 as cancelled_value_idr
    , round(100.0 * p.cancelled_orders / nullif(p.all_orders, 0), 1)                     as cancellation_rate_pct
from {{ ref('dim_salesperson') }} s
left join per_salesperson p on p.salesperson_id = s.salesperson_id