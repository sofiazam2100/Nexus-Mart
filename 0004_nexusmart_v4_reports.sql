-- Server-side reporting view with safe invoker semantics.
create or replace view public.branch_daily_sales
with (security_invoker = true)
as
select
  s.organization_id,
  s.branch_id,
  (s.created_at at time zone 'Asia/Qatar')::date as sale_date,
  count(*) as invoice_count,
  sum(s.subtotal_minor) as subtotal_minor,
  sum(s.discount_minor) as discount_minor,
  sum(s.total_minor) as sales_minor,
  sum(s.cost_minor) as cogs_minor,
  sum(s.total_minor - s.cost_minor) as gross_profit_minor,
  sum(s.paid_minor) as paid_minor,
  sum(s.due_minor) as due_minor
from public.sales s
where s.status = 'posted'
group by s.organization_id,s.branch_id,(s.created_at at time zone 'Asia/Qatar')::date;

grant select on public.branch_daily_sales to authenticated;
