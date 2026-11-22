# FlexyPack – Salesperson Performance (dbt + PostgreSQL)

A dbt project on a copy of FlexyPacks Odoo sales data. It builds a tested, documented model of the sales team's performance, ending in `rpt_salesperson_performance` (one row per salesperson).

The summary for the sales director is in `Flexypack_Data_Assessment_Findings.pdf`.

---

## How to run

**Versions used and tested:**

| Tool | Version |
|---|---|
| Python | 3.12.10 |
| dbt-core | 1.12.7 |
| dbt-postgres | 1.11.0 |
| PostgreSQL | 16 (Docker image `postgres:16`, from the provided `docker-compose.yml`) |
| Docker | 29.9.3, Docker Compose v5.7.0 |
| Git | 2.51.0 |
| OS | Windows 11 (PowerShell) |

**1. Start the provided database from scratch** (in the folder of the provided `takehome_pg.zip`):
```bash
docker compose down -v   # only if it ran before
docker compose up -d
docker compose ps        
```

**2. Install dbt** (in the root of this repository):
```bash
python -m venv .venv
# Windows PowerShell:
.venv\Scripts\Activate.ps1
# macOS / Linux:
source .venv/bin/activate

python -m pip install -r requirements.txt (i have listed the requirements in the txt)
```
Versions are pinned on purpose: an unpinned `pip install dbt-postgres` currently resolves to a pre-release of dbt-core.

**3. Build and test everything:**
```bash
cd flexypack_analytics
dbt debug     # checks the connection
dbt build     # builds all models and runs all tests
```
Expected result: should be about 12 models, and 43 tests.

If Windows blocks `dbt.exe` ("An Application Control policy has blocked this file", from Smart App Control), run dbt through Python instead: `python -c "from dbt.cli.main import cli; cli()" build`.

`flexypack_analytics/profiles.yml` holds the connection to the provided database (localhost:5433, user and password `analyst`).  With real credentials I would not commit the pass and use environment variables instead.

**Optional:**
```bash
dbt docs generate && dbt docs serve   # documentation site with column descriptions and lineage graph
dbt compile                           
```

---

## Project structure

Three layers. Everything is built in the `analytics` schema, the source schema 'odoo' is treated as read-only.

| Layer | Folder | Prefix | Materialization | Purpose |
|---|---|---|---|---|
| Staging | `models/staging` | `stg_odoo__` | view | One model per source table: rename, cast, light cleaning |
| Facts & dimensions | `models/facts`, `models/dimensions` | `fact_`, `dim_` | table | Business logic: what counts as a sale, revenue, cost, margin |
| Reports | `models/reports` | `rpt_` | table | One business question per model (the mart) |

Staging models are views (cheap, always current). Facts, dimensions and reports are tables (queried directly, stable between builds).

```
flexypack_analytics/
├─ models/
│  ├─ staging/      stg_odoo__*            7 views, one per source table + _odoo__sources.yml
│  ├─ dimensions/   dim_salesperson, dim_customer, dim_product
│  ├─ facts/        fact_order_lines
│  └─ reports/      rpt_salesperson_performance
├─ tests/           assert_report_revenue_matches_fact.sql
└─ analyses/        data_profiling.sql and the drill-downs behind the findings
```

### Staging conventions
- Primary keys renamed to `<entity>_id`; foreign keys named after what they point to (`customer_id`, `salesperson_id`).
- Text columns trimmed; empty strings turned into NULL (`nullif(trim(x), '')`). Status values lower-cased.
- Units in column names: money `_idr`, percentages `_pct`.
- Timestamps kept in UTC (`_at_utc`) and converted to Jakarta time (`_at_wib`, `Asia/Jakarta`, UTC+7); order date for reporting is `order_date_wib`.
- Booleans prefixed `is_`.
- No filtering, joins or business rules in staging; cancelled orders are kept here and handled in the facts.

---

## Data exploration and quality checks

Before modeling, I  ocheck the odoo for what can we use and be trusted. The database already have uprimary keys and valid references (foreign keys), so the checks focus on what it does not enforce: business keys, empty values, consistency between redundant columns, and business meaning.

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
The data is generalyy consistent, cleaner than i expected to be honest: link or joins, line and order calculations, salesperson attribution, currency and dates are all good, and there are no duplicates or impossible values. The main trust issue is cancelled orderswhich they are 28 % of all order value, include the largest deals, and are concentrated in two salespeople. they are excluded from revenue and reported separately as a cancellation rate.

---

## Issues found and how I handled them

| Issue | How I handled it |
|---|---|
| 19 of 116 orders (28 % of order value) are cancelled, including the largest deals, and 18 of them belong to two salespeople | Excluded from revenue, margin, discount and order counts via `is_valid_sale`; kept in the fact and reported separately as cancelled orders, cancelled value and cancellation rate |
| Timestamps are stored in UTC, the business runs on Jakarta time | Converted in staging (`Asia/Jakarta`); dates reported in WIB. No order changes month, but the calendar day can |
| `res_partner.customer_rank_active` its value is all true and i could not figure out what its for | Kept in staging, not used anywhere |
| The salesperson appears in three places (order, order line, customer owner) | all three agree, sales are credited by the orders salesperson |
| Odoo names are hard to read (`standard_price` is cost, `product_tmpl_id`, `categ_id`, `price_subtotal`) | Renamed in staging with units in the names (`_idr`, `_pct`); `standard_price` documented as unit cost |
| Text fields may carry stray spaces or empty strings although considering how clean the data is very unlikely| Trimmed and empty strings turned into NULL in staging |
| No historical cost on order lines | Current product cost used, stated as an assumption below |

Everything else checked out (no duplicates, no orphans, no impossible values ex.negative unit price, all totals reconcile), see the full table above.

## Assumptions

- The data is one month: September 2026 (all orders fall between 1 and 30 September, in UTC and in WIB).
- Only orders in state `sale` or `done` are counted as real sales; `cancel` is left out.
- `res_users` holds the salespeople, as the source README says; all 10 are active, named people.
- we dont include tax in revenue (tax is not company income).
- Discount is a percentage of the unit price (

## Modeling decisions
- Revenue counts only orders in state `sale` or `done`; `cancel` is excluded.
- Sales are credited to the salesperson on the order (salesperson id in the order table).
- `res_users` is treated as the salesperson list, just like the instruction said.
- Line revenue = `price_subtotal` its after discount and no include tax.
- Unit cost = `product_template.standard_price`. Assumption: this is the current cost, not the cost at the time of sale or not the price listed to the customer, should be the price we use to calculate cost.
- Dates are reported in Jakarta time (WIB).
- `fact_order_lines` keeps every order line (295), including cancelled ones, with an `is_valid_sale` flag. Revenue and margin are summed only where the flag is true, cancelled lines stay so the cancellation rate can be calculated from the same table.
- Salesperson, customer, date and state on the fact come from the order header (the business record), cost comes from `dim_product`.
- Reconciliation of the fact against the profiling results: 295 lines, 97 valid orders, valid revenue Rp 1,893,238,650 and cancelled value Rp 723,107,800, all matching. Valid gross margin is Rp 432,553,650.
- I only  make one fact table, that is the order line grain level. Order level metrics can be derived by distinct counts, which avoids two fact tables that could drift apart, less table to maintan as well.
- The report starts from `dim_salesperson` with a left join, so every salesperson appears, even one without sales.
- The drill-downs behind the findings (by customer, by product) are kept in `analyses/`, not as models: they answered a one-off question and one of them names specific salespeople, which does not belong in a reusable report.

## Metric definitions

All metrics in `rpt_salesperson_performance` are per salesperson, for the period in the data (September 2026), in IDR excluding tax. "Confirmed orders" = state `sale` or `done`. The same definitions are in the model's column descriptions.

| Column | Definition |
|---|---|
| `revenue_idr` | Sum of line amounts after discount (`price_subtotal`) on confirmed orders |
| `gross_margin_idr` | Revenue minus product cost (quantity × current unit cost) on confirmed orders |
| `gross_margin_pct` | Gross margin ÷ revenue |
| `margin_before_discount_pct` | Margin % the same products would have earned at list price; depends only on the product mix. Compared with `gross_margin_pct`, it shows how much margin was given away as discount |
| `avg_discount_pct` | Total discount ÷ total value before discount (weighted, so large lines count more than small ones) |
| `orders` | Number of confirmed orders |
| `avg_order_value_idr` | Revenue ÷ number of confirmed orders |
| `categories_sold` | Number of distinct product categories sold (out of 4) – the breadth measure |
| `customers` | Number of distinct customers with a confirmed order |
| `customer_cities` | Number of distinct customer cities with a confirmed order |
| `cancelled_orders` | Number of cancelled orders |
| `cancelled_value_idr` | Value of cancelled orders (not included in revenue) |
| `cancellation_rate_pct` | Cancelled orders ÷ all orders |

Revenue, margin, discount, orders, average order value and category breadth are the metrics the brief asks for; margin before discount, customers and the cancellation metrics were added because the data showed they explain the differences between salespeople.

## Tests

`dbt build` runs 43 tests, all passing:

most of the taests are just unique and not null, other than that are teh desc
- **`unique` + `not_null`** on the primary key of every model (staging, dimensions, fact, report).
- **`accepted_values`** on the order state (`sale`, `done`, `cancel`): a new Odoo state would fail the build instead of being silently counted or dropped.
- **`relationships`**: every order line belongs to an order; every fact row links to an existing salesperson, customer and product; every customer's salesperson exists.
- **`not_null`** on unit cost (margin cannot be calculated without it) and on the `is_valid_sale` flag.
- **Singular test** `assert_report_revenue_matches_fact`: the report's total revenue must equal the confirmed revenue in the fact table, which catches a join in the report that drops or duplicates revenue.

## What I would do with more time


- Scheduling: run `dbt build` on a schedule right after the Odoo replica is refreshed maybe with airflow or script, 
- Monitoring: `dbt source freshness` on `write_date`, it can alerts us if any refresh failed and eal time data is not available.
- Historical snapshot: in my current company we have snapshot schema which stores historical state of core tables particularly with moving statuses so we can check their past condition
- Dashboard : an auto refresh dashboard for weekly/monthly monitoring purposes.

## Time spent
18 Nov 2026 :  4-5 hours (making the staging, but mainly downloading and setting up the tools, docker, PyCharm, dbeaver etc)
20 Nov 2026 : 2-3 hours  (building the fact-dim tables)
22 Nov 2026 : 4-5 hours (building  rpt, data exploration, insight analysis & writing. Finalizing)

Total of : 10-13 hours, on full time undisturbed work environment thats around 2 man days. Normal considering we are bulding the models from scratch

## Use of generative AI
- I plan out the steps of work, the ai refine it, also help me keep track in the flow when i stray apart from it
- help me with dbt commands and other syntax that i know what its for but dont usually memorize
- draft out test for the data, while unique and null values are common, there are stuff like, does the same column name on 2 tables have the same value ? any table could result in fail jons ? any impossible values such as negative item price ? and many more of edge cases like that a single human being cannot come up with all of the test.
- help with weird errors that would just slows me down for no good reason, such as when using cte you have to select all the query  first in order to run it without error on posgree + dbeaver, it doesn't have to be like that on redshift + metabase. Without ai thats like 15-20  minutes wasted for trivial stuff.
- rechecking the whole architecture after i build it
-discussion partners on wether we should integrate the product into 1 table on dim and many other cases.
-drafted parts of the code and documentation (some models, the test YAML and README sections), which I reviewed, ran and checked against my own exploration numbers. This decision is made to avoid incomplete information on the readme and test such as on how to run this project if written by me individually.
