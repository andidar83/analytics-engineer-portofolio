with source as(
	select * from {{ source('odoo', 'product_product') }}
),

renamed as (
	select
	id as product_id
	, product_tmpl_id as product_template_id
	, nullif(trim(default_code),'') as product_code
	, active as is_active
	from source
)

select * from renamed