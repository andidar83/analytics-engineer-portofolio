with salespersons as (
	select * from {{ ref('stg_odoo__res_users') }}
)

select
	salesperson_id
	, salesperson_name
	, salesperson_email_login
	, is_active
from salespersons