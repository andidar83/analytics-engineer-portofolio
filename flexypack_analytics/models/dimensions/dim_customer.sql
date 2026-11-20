with customers as (
	select * from {{ ref('stg_odoo__res_partner') }}
)

select
    customer_id
	,customer_name
	,city
	,country
	,is_active_customer
	,salesperson_id
from customers