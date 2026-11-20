with lines as(
    select * from {{ ref('stg_odoo__sale_order_line')}}
)
, orders as (
    select * from {{ ref('stg_odoo__sale_order')}}
)

, products as (
    select * from {{ ref('dim_product')}}
)

select
	-- keys
	l.order_line_id
	, l.order_id
	, o.order_number
	, o.salesperson_id
	, o.customer_id
	, l.product_id
	, p.product_category_id

	-- dates and status
	, o.ordered_at_wib
	, o.order_date_wib
	, o.order_state
	, o.order_state in ('sale', 'done') as is_valid_sale

	-- quantities and prices
	, l.quantity
	, l.unit_price_idr
	, l.discount_pct

	-- amounts
	, l.quantity * l.unit_price_idr                          as gross_amount_idr
	, l.quantity * l.unit_price_idr - l.subtotal_idr         as discount_amount_idr
	, l.subtotal_idr                                         as revenue_idr
	, p.standard_price_idr                                   as unit_cost_idr
	, l.quantity * p.standard_price_idr                      as cost_idr
	, l.subtotal_idr - l.quantity * p.standard_price_idr     as gross_margin_idr

from lines l
join orders o on o.order_id = l.order_id
left join products p on p.product_id = l.product_id