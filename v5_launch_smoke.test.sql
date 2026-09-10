-- Run in a test project after migrations.
select to_regclass('public.subscription_plans') is not null as subscription_plans_exists;
select to_regclass('public.organization_subscriptions') is not null as organization_subscriptions_exists;
select exists(select 1 from public.subscription_plans where code='starter') as starter_plan_seeded;
