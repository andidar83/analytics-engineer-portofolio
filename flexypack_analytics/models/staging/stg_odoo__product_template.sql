with source as(
	select * from  {{ source('odoo', 'product_template') }}
),

renamed as (
	select
	id as product_template_id
	, nullif(trim(name),'') as product_name
	, nullif(trim(default_code),'') as product_code
	, categ_id as product_category_id
	, nullif(trim(type),'') as types
	, list_price as list_price_idr
	, standard_price as standard_price_idr
	, nullif(trim(uom_name),'') as unit_of_measure
	, active as is_active
	from source
)

select * from renamed
