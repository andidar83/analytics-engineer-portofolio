with source as (
	select * from {{ source('odoo', 'sale_order_line') }}
),

renamed as (
	select
	id as order_line_id
	, order_id as order_id
	, sequence as line_sequence
	, product_id as product_id
	, product_template_id as product_template_id
	, nullif(trim(name), '') as line_description

	, product_uom_qty as quantity
	, nullif(trim(product_uom), '') as unit_of_measure
	, price_unit as unit_price_idr
	, discount as discount_pct
	, price_subtotal as subtotal_idr
	, price_tax as tax_idr
	, price_total as total_idr

	, lower(trim(state)) as line_state
	, salesman_id as line_salesperson_id
	, order_partner_id as line_customer_id

	, create_date as created_at_utc
	, (create_date at time zone 'UTC') at time zone 'Asia/Jakarta' as created_at_wib
	from source
)

select * from renamed