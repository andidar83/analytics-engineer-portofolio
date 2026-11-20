with products as (
	select * from {{ ref('stg_odoo__product_product') }}
),

templates as (
	select * from {{ ref('stg_odoo__product_template') }}
),

categories as (
	select * from {{ ref('stg_odoo__product_category') }}
)

select
	p.product_id
	, p.product_template_id
	, p.product_code
	, t.product_name
	, t.product_category_id
	, c.category_name
	, t.types
	, t.list_price_idr
	, t.standard_price_idr
	, t.unit_of_measure
	, (p.is_active and t.is_active) as is_active
from products p
left join templates t on t.product_template_id = p.product_template_id
left join categories c on c.product_category_id = t.product_category_id