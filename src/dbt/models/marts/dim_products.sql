with products as (
    select * from {{ ref('stg_products') }}
)

select
    product_id,
    product_name,
    category,
    brand,
    department,
    cost,
    retail_price,
    round(retail_price - cost, 2) as profit_margin,
    round(safe_divide(retail_price - cost, retail_price) * 100, 2) as profit_margin_percent,
    distribution_center_id
from products
