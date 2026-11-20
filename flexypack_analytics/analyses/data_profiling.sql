-- Data profiling of the odoo source schema.
-- Numbers match the "Data exploration and quality checks" table in the README.
-- Plain SQL against the raw tables; run in any SQL client. Not built by dbt.


-- 1. Order states
select state, count(*) as orders
from odoo.sale_order
group by state
order by orders desc;


-- 2. Row counts per table
select 'sale_order' as table_name, count(*) as row_count from odoo.sale_order
union all select 'sale_order_line',  count(*) from odoo.sale_order_line
union all select 'res_partner',      count(*) from odoo.res_partner
union all select 'res_users',        count(*) from odoo.res_users
union all select 'product_template', count(*) from odoo.product_template
union all select 'product_product',  count(*) from odoo.product_product
union all select 'product_category', count(*) from odoo.product_category;


-- 3. customer_rank_active: values, and customers with / without orders
select
    p.customer_rank_active,
    count(distinct p.id)          as customers,
    count(distinct o.partner_id)  as customers_with_orders,
    count(o.id)                   as orders
from odoo.res_partner p
left join odoo.sale_order o on o.partner_id = p.id
group by p.customer_rank_active;


-- 4. Order salesperson vs customer's assigned salesperson
select
    count(*)                                                       as orders,
    count(*) filter (where o.user_id = p.user_id)                  as same_as_owner,
    count(*) filter (where o.user_id <> p.user_id)                 as different,
    count(*) filter (where o.user_id is null or p.user_id is null) as one_missing
from odoo.sale_order o
join odoo.res_partner p on p.id = o.partner_id;


-- 5. Line salesperson vs order salesperson
select
    count(*)                                                            as lines,
    count(*) filter (where l.salesman_id = o.user_id)                   as same_as_order,
    count(*) filter (where l.salesman_id <> o.user_id)                  as different,
    count(*) filter (where l.salesman_id is null or o.user_id is null)  as one_missing
from odoo.sale_order_line l
join odoo.sale_order o on o.id = l.order_id;


-- 6. Line state vs order state
select o.state as order_state, l.state as line_state, count(*) as lines
from odoo.sale_order_line l
join odoo.sale_order o on o.id = l.order_id
group by 1, 2
order by 1, 2;


-- 7. Line subtotal = qty x unit price x (1 - discount %)
select
    count(*) as lines,
    count(*) filter (
        where abs(price_subtotal - round(product_uom_qty * price_unit * (1 - discount / 100), 2)) > 1
    ) as subtotal_mismatch
from odoo.sale_order_line;


-- 8. Order amount_untaxed = sum of its lines
with line_totals as (
    select order_id, sum(price_subtotal) as lines_subtotal
    from odoo.sale_order_line
    group by order_id
)
select
    count(*) as orders,
    count(*) filter (where abs(o.amount_untaxed - coalesce(lt.lines_subtotal, 0)) > 1) as header_mismatch
from odoo.sale_order o
left join line_totals lt on lt.order_id = o.id;


-- 9. Line product vs product template
select count(*) as template_mismatch
from odoo.sale_order_line l
left join odoo.product_product pp on pp.id = l.product_id
where l.product_template_id is distinct from pp.product_tmpl_id;


-- 10. Products with missing, zero, or too-high cost
select id, name, list_price, standard_price
from odoo.product_template
where standard_price is null
   or standard_price <= 0
   or standard_price >= list_price;


-- 11. Currency
select currency, count(*) as orders, sum(amount_untaxed) as untaxed
from odoo.sale_order
group by currency;


-- 12. amount_total = amount_untaxed + amount_tax
select count(*) filter (where abs(amount_total - (amount_untaxed + amount_tax)) > 1) as total_mismatch
from odoo.sale_order;


-- 13. Lines sold at a price different from the list price
select pt.name, pt.list_price, l.price_unit, l.discount, count(*) as lines
from odoo.sale_order_line l
join odoo.product_template pt on pt.id = l.product_template_id
where l.price_unit <> pt.list_price
group by 1, 2, 3, 4
order by lines desc;


-- 14. Largest order lines
select l.id, o.name, o.state, l.product_uom_qty, l.price_unit, l.discount, l.price_subtotal
from odoo.sale_order_line l
join odoo.sale_order o on o.id = l.order_id
order by l.price_subtotal desc
limit 10;


-- 15. Time zone: date range, and orders that change month when converted UTC -> WIB
select
    min(date_order) as first_order_utc,
    max(date_order) as last_order_utc,
    count(*) filter (
        where date_trunc('month', date_order)
           <> date_trunc('month', (date_order at time zone 'UTC') at time zone 'Asia/Jakarta')
    ) as orders_changing_month
from odoo.sale_order;


-- 16. Order value by state
select state, count(*) as orders, sum(amount_untaxed) as untaxed_idr, round(avg(amount_untaxed)) as avg_order_idr
from odoo.sale_order
group by state
order by untaxed_idr desc;


-- 17. Cancellations per salesperson
select
    u.name,
    count(*)                                                        as total_orders,
    count(*) filter (where o.state = 'cancel')                      as cancelled_orders,
    sum(o.amount_untaxed) filter (where o.state = 'cancel')         as cancelled_value_idr,
    sum(o.amount_untaxed) filter (where o.state in ('sale','done')) as valid_value_idr
from odoo.sale_order o
join odoo.res_users u on u.id = o.user_id
group by u.name
order by cancelled_value_idr desc nulls last;


-- 18. Duplicate order numbers
select name, count(*) as n, string_agg(id::text, ', ') as ids, string_agg(state, ', ') as states
from odoo.sale_order
group by name
having count(*) > 1;


-- 19. Impossible or unusual line values
select
    count(*) filter (where product_uom_qty <= 0)           as qty_zero_or_negative,
    count(*) filter (where price_unit <= 0)                as price_zero_or_negative,
    count(*) filter (where discount < 0 or discount > 100) as discount_out_of_range,
    count(*) filter (where discount > 0)                   as lines_with_discount,
    max(discount)                                          as max_discount
from odoo.sale_order_line;


-- 20. Duplicate-looking lines (same order, product, quantity and price)
select order_id, product_id, product_uom_qty, price_unit, count(*) as n, string_agg(id::text, ', ') as line_ids
from odoo.sale_order_line
group by order_id, product_id, product_uom_qty, price_unit
having count(*) > 1;


-- 21. Orders without lines
select o.id, o.name, o.state, o.amount_untaxed
from odoo.sale_order o
left join odoo.sale_order_line l on l.order_id = o.id
where l.id is null;


-- 22. Small tables, read in full
select * from odoo.res_users order by id;
select * from odoo.product_category order by id;
select * from odoo.product_template order by categ_id, name;
select * from odoo.res_partner order by name;


-- 23. Valid sales by inactive salespeople or of inactive products
select 'inactive salesperson' as issue, u.name as name, count(distinct o.id) as orders
from odoo.sale_order o
join odoo.res_users u on u.id = o.user_id
where u.active = false
  and o.state in ('sale', 'done')
group by u.name
union all
select 'inactive product', pt.name, count(distinct l.order_id)
from odoo.sale_order_line l
join odoo.sale_order o       on o.id = l.order_id
join odoo.product_product pp on pp.id = l.product_id
join odoo.product_template pt on pt.id = pp.product_tmpl_id
where (pp.active = false or pt.active = false)
  and o.state in ('sale', 'done')
group by pt.name;


-- 24. Date sanity: order date vs create / write date
select
    count(*) filter (where write_date < create_date)                 as updated_before_created,
    count(*) filter (where date_order > write_date)                  as ordered_after_last_update,
    min(date_order - create_date)                                    as min_gap_order_vs_created,
    max(date_order - create_date)                                    as max_gap_order_vs_created
from odoo.sale_order;
