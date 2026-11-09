with order_items as (
    select * from {{ ref('fct_order_items') }}
),

orders as (
    select * from {{ ref('stg_orders') }}
),

aggregated as (
    select
        order_id,
        count(order_item_id) as actual_item_count,
        round(sum(sale_price), 2) as order_total_amount,
        round(sum(cost), 2) as order_total_cost,
        round(sum(gross_margin), 2) as order_total_margin,
        max(case when is_returned then 1 else 0 end) as has_returned_items
    from order_items
    group by order_id
)

select
    o.order_id,
    o.user_id,
    o.order_status,
    o.gender,
    o.created_at,
    o.shipped_at,
    o.delivered_at,
    o.returned_at,
    coalesce(a.actual_item_count, o.item_count) as item_count,
    coalesce(a.order_total_amount, 0) as total_amount,
    coalesce(a.order_total_cost, 0) as total_cost,
    coalesce(a.order_total_margin, 0) as total_margin,
    case when a.has_returned_items = 1 then true else false end as is_returned
from orders o
left join aggregated a on o.order_id = a.order_id
