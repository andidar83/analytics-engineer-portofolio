# FlexyPack – Salesperson Performance (dbt + PostgreSQL)

A dbt project on a copy of FlexyPack's Odoo sales data. It builds a tested, documented model of the sales team's performance, ending in `rpt_salesperson_performance` (one row per salesperson).

> Sections marked _(to do)_ are not finished yet.

---

## How to run
_(to do: exact commands from a fresh database to `dbt build`)_

**Versions:** Python 3.12, dbt-core 1.12.7, dbt-postgres 1.11.0, PostgreSQL 16 (Docker image `postgres:16`).

---

## Project structure

Three layers, as in the brief. Everything is built in the `analytics` schema; the source schema `odoo` is treated as read-only.

| Layer | Folder | Prefix | Materialization | Purpose |
|---|---|---|---|---|
| Staging | `models/staging` | `stg_odoo__` | view | One model per source table: rename, cast, light cleaning |
| Facts & dimensions | `models/facts`, `models/dimensions` | `fct_`, `dim_` | table | Business logic: what counts as a sale, revenue, cost, margin |
| Reports | `models/reports` | `rpt_` | table | One business question per model (the mart) |

Staging models are views (cheap, always current). Facts, dimensions and reports are tables (queried directly, stable between builds).

### Staging conventions
- Primary keys renamed to `<entity>_id`; foreign keys named after what they point to (`customer_id`, `salesperson_id`).
- Text columns trimmed; empty strings turned into NULL (`nullif(trim(x), '')`). Status values lower-cased.
- Units in column names: money `_idr`, percentages `_pct`.
- Timestamps kept in UTC (`_at_utc`) and converted to Jakarta time (`_at_wib`, `Asia/Jakarta`, UTC+7); order date for reporting is `order_date_wib`.
- Booleans prefixed `is_`.
- No filtering, joins or business rules in staging; cancelled orders are kept here and handled in the facts.

---

## Data exploration and quality checks

Before modeling, I treated the `odoo` schema as a production copy and checked what can be trusted. The database already enforces unique ids (primary keys) and valid references (foreign keys), so the checks focus on what it does not enforce: business keys, empty values, consistency between redundant columns, and business meaning.

Queries: `flexypack_analytics/analyses/data_profiling.sql`.

### Results

| # | Check | Result | Decision |
|---|---|---|---|
| 1 | Order states | `sale` 58, `done` 39, `cancel` 19 (116 orders) | Only `sale` and `done` count as sales (97 orders) |
| 2 | Row counts | orders 116, lines 295, customers 40, users 10, product templates 20, product variants 20, categories 4 | Baseline; staging keeps the same row counts |
| 3 | `res_partner.customer_rank_active` | `true` for all 40 customers; 36 have orders, 4 have none | Not a standard Odoo field and carries no information; kept in staging, not used |
| 4 | Order salesperson vs customer's assigned salesperson | Identical for all 116 orders, none missing | – |
| 5 | Line salesperson vs order salesperson | Identical for all 295 lines; every line belongs to an existing order | Sales credited to the order's salesperson (`sale_order.user_id`) |
| 6 | Line state vs order state | Consistent: cancel 54 lines, done 106, sale 135 | Cancelled sales can be excluded at order level |
| 7 | Line subtotal = qty × unit price × (1 − discount %) | 0 mismatches out of 295 | `price_subtotal` used as line revenue (after discount, before tax); `discount` confirmed as a percentage |
| 8 | Order `amount_untaxed` = sum of its lines | 0 mismatches out of 116 | Order and line level give the same revenue |
| 9 | Line product vs product template | 0 mismatches | Category and cost can be taken from the template |
| 10 | Product costs (missing, zero, or ≥ list price) | None | `standard_price` used as unit cost for gross margin |
| 11 | Currency | All 116 orders in IDR | No conversion needed |
| 12 | `amount_total` = `amount_untaxed` + `amount_tax` | 0 mismatches | – |
| 13 | Unit price vs list price | Every line sold at list price | Discounts appear only in the `discount` column; average discount is based on it |
| 14 | Largest order lines | 5 of the 10 largest lines are cancelled, including the 3 largest | Including cancelled orders would heavily overstate revenue |
| 15 | Time zone: date range, and orders that change month when converted from UTC to WIB | 1–30 Sep 2026 (UTC); 0 orders change month | The period is September 2026. Dates are still reported in WIB because the calendar day can shift for orders after 17:00 UTC |
| 16 | Order value by state | `sale` Rp 971,992,475 (58 orders); `done` Rp 921,246,175 (39); `cancel` Rp 723,107,800 (19). Average cancelled order Rp 38.1M vs Rp 16.8M (`sale`) and Rp 23.6M (`done`) | Valid revenue is Rp 1,893,238,650. Cancelled orders are 28 % of all order value; counting them would overstate revenue by 38 % |
| 17 | Cancellations per salesperson | Joko Setiawan 10 of 19 orders cancelled (Rp 381.0M), Irfan Hakim 8 of 19 (Rp 329.9M), Hana Kusuma 1 of 12 (Rp 12.2M); all others 0 | Two salespeople hold 18 of 19 cancellations and 98 % of cancelled value. With cancelled orders included they would rank #1 and #2 on revenue; on valid sales they rank #5 and #4. Cancellation rate is added to the report |
| 18 | Duplicate order numbers | None | – |
| 19 | Line values: quantity ≤ 0, price ≤ 0, discount outside 0–100 %, maximum discount | None out of range; ~249 of 295 lines have a discount; maximum discount 39.5 % | Discount values can be used as they are |
| 20 | Duplicate-looking lines (same order, product, quantity, price) | None | – |
| 21 | Orders without lines | None | – |
| 22 | Small tables read in full (users, categories, products, customers) | Users: 10 named salespeople, all active, no admin or system users. Categories: 4 flat categories (Sachet, Label, Paper Cup, Standing Pouch), no parent category. Customers: 40 companies in Indonesia, no duplicates or test records seen | All users are treated as salespeople. Category breadth is counted over these 4 categories (maximum 4) |
| 23 | Valid sales by inactive salespeople or of inactive products | None | – |
| 24 | Date sanity (order date vs create/write date) | `date_order` equals `create_date` for every order; no `write_date` before `create_date` | Dates are reliable |

### Summary
The data is internally consistent: links, line and order arithmetic, salesperson attribution, currency and dates all reconcile, and there are no duplicates or impossible values. The main trust issue is cancelled orders: they are 28 % of all order value, include the largest deals, and are concentrated in two salespeople. Counting them would overstate revenue by 38 % and reverse the salesperson ranking, so they are excluded from revenue and reported separately as a cancellation rate.

---

## Modeling decisions
- Revenue counts only orders in state `sale` or `done`; `cancel` is excluded.
- Sales are credited to the salesperson on the order (`sale_order.user_id`).
- `res_users` is treated as the salesperson list, as stated in the source README.
- Line revenue = `price_subtotal` (after discount, excluding tax).
- Unit cost = `product_template.standard_price`. Assumption: this is the current cost, not the cost at the time of sale (Odoo does not store historical cost on the order line).
- Dates are reported in Jakarta time (WIB).
- _(to do: facts, dimensions, report)_

## Metric definitions
_(to do)_

## Tests
_(to do)_

## What I would do with more time
_(to do)_

## Time spent
_(to do)_

## Use of generative AI
_(to do)_
