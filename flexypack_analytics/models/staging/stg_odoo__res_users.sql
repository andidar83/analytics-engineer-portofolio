select
    id      as user_id,
    name    as user_name,
    login   as user_login,
    active  as is_active
from {{ source('odoo', 'res_users') }}