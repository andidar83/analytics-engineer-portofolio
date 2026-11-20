with source as (
	select * from {{ source('odoo', 'sale_order') }}
),

renamed as (
	select
	id as order_id
	, nullif(trim(name), '') as order_number
	, partner_id as customer_id
	, user_id as salesperson_id
	, lower(trim(state)) as order_state

	, date_order as ordered_at_utc
	, (date_order at time zone 'UTC') at time zone 'Asia/Jakarta' as ordered_at_wib
	, ((date_order at time zone 'UTC') at time zone 'Asia/Jakarta')::date as order_date_wib

	, amount_untaxed as amount_untaxed_idr
	, amount_tax as amount_tax_idr
	, amount_total as amount_total_idr
	, upper(trim(currency)) as currency

	, create_date as created_at_utc
	, (create_date at time zone 'UTC') at time zone 'Asia/Jakarta' as created_at_wib
	, write_date as updated_at_utc
	, (write_date at time zone 'UTC') at time zone 'Asia/Jakarta' as updated_at_wib
	from source
)

select * from renamed