with users as (
    select * from {{ ref('stg_users') }}
)

select
    user_id,
    full_name,
    email,
    age,
    case
        when age < 20 then 'Under 20'
        when age between 20 and 29 then '20-29'
        when age between 30 and 39 then '30-39'
        when age between 40 and 49 then '40-49'
        when age between 50 and 59 then '50-59'
        else '60+'
    end as age_bracket,
    gender,
    city,
    state,
    country,
    traffic_source,
    created_at as registered_at
from users
