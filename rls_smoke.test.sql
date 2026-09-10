-- Smoke-test checklist for Supabase CLI / pgTAP.
-- Full auth fixture creation depends on your project's configured test helpers.
begin;

select plan(4);

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='sales' and policyname is null
  ),
  'sales has named RLS policies'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='sales'
  ),
  'sales RLS policies exist'
);

select ok(
  exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='checkout_sale'
  ),
  'checkout_sale exists'
);

select ok(
  exists (
    select 1 from pg_views
    where schemaname='public' and viewname='branch_daily_sales'
  ),
  'reporting view exists'
);

select * from finish();
rollback;
