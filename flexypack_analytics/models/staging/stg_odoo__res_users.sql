with source as(
	select * from {{ source('odoo', 'res_users') }}
),

renamed as (
	select
	id as salesperson_id
	, nullif(trim(name),'') as salesperson_name
	, nullif(trim(login),'') as salesperson_email_login
	, active as is_active
	from source
)

select * from renamed




