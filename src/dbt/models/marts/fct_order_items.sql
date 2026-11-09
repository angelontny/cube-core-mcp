with order_items as (
    select * from {{ ref('stg_order_items') }}
),

orders as (
    select * from {{ ref('stg_orders') }}
),

products as (
    select * from {{ ref('stg_products') }}
)

select
    oi.order_item_id,
    oi.order_id,
    oi.user_id,
    oi.product_id,
    oi.item_status,
    o.order_status,
    oi.created_at as ordered_at,
    oi.shipped_at,
    oi.delivered_at,
    oi.returned_at,
    oi.sale_price,
    p.cost,
    round(oi.sale_price - p.cost, 2) as gross_margin,
    case when oi.returned_at is not null then true else false end as is_returned,
    case when oi.delivered_at is not null then true else false end as is_delivered
from order_items oi
left join orders o on oi.order_id = o.order_id
left join products p on oi.product_id = p.product_id
