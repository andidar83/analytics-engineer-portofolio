with source as(
	select * from {{ source('odoo', 'res_partner') }}
),

renamed as (
	select
	id as customer_id
	, nullif(trim(name),'') as customer_name
	, nullif(trim(city),'') as city
	, nullif(trim(country),'') as country
	, customer_rank_active as is_active_curtomer
	, user_id as salesperson_id
	from source
)

select * from renamed