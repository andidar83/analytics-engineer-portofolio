with source as(
	select * from {{ source('odoo', 'product_category') }}
),

renamed as (
	select
	id as product_category_id
	, nullif(trim(name),'') as category_name
	, nullif(trim(complete_name),'') as category_complete_name
	, parent_id as parent_id
	from source
)

select * from renamed