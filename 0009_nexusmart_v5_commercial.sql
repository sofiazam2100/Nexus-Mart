-- NexusMart V5 Commercial Launch hardening
-- Financial operations remain server-side; this migration adds launch controls.

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  monthly_price_minor bigint not null default 0 check(monthly_price_minor >= 0),
  max_branches integer not null default 1 check(max_branches > 0),
  max_members integer not null default 3 check(max_members > 0),
  max_products integer not null default 1000 check(max_products > 0),
  features jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.organization_subscriptions (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id),
  status text not null default 'trial' check(status in ('trial','active','past_due','cancelled','expired')),
  trial_ends_at timestamptz,
  current_period_start timestamptz,
  current_period_end timestamptz,
  provider text,
  provider_customer_id text,
  provider_subscription_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.subscription_plans(code,name,monthly_price_minor,max_branches,max_members,max_products,features)
values
('starter','Starter',4900,1,3,1000,'{"reports":true,"whatsapp_receipt":true}'::jsonb),
('growth','Growth',9900,3,10,10000,'{"reports":true,"whatsapp_receipt":true,"advanced_inventory":true,"multi_branch":true}'::jsonb),
('pro','Pro',19900,10,30,50000,'{"reports":true,"whatsapp_receipt":true,"advanced_inventory":true,"multi_branch":true,"audit":true,"priority_support":true}'::jsonb)
on conflict(code) do nothing;

alter table public.subscription_plans enable row level security;
alter table public.organization_subscriptions enable row level security;

drop policy if exists "plans_read_authenticated" on public.subscription_plans;
create policy "plans_read_authenticated" on public.subscription_plans for select to authenticated using(active=true);

drop policy if exists "org_subscription_read_member" on public.organization_subscriptions;
create policy "org_subscription_read_member" on public.organization_subscriptions for select to authenticated
using (organization_id = public.auth_org_id());

create index if not exists idx_org_subscriptions_status on public.organization_subscriptions(status);
create index if not exists idx_org_subscriptions_period on public.organization_subscriptions(current_period_end);

create or replace function public.start_trial(p_plan_code text default 'starter')
returns public.organization_subscriptions
language plpgsql security definer set search_path=''
as $$
declare v_org uuid; v_plan public.subscription_plans; v_row public.organization_subscriptions;
begin
  select public.auth_org_id() into v_org;
  if v_org is null then raise exception 'Not authorized'; end if;
  select * into v_plan from public.subscription_plans where code=p_plan_code and active=true limit 1;
  if not found then raise exception 'Plan not found'; end if;
  insert into public.organization_subscriptions(organization_id,plan_id,status,trial_ends_at,current_period_start,current_period_end)
  values(v_org,v_plan.id,'trial',now()+interval '14 days',now(),now()+interval '14 days')
  on conflict(organization_id) do update set plan_id=excluded.plan_id,status='trial',trial_ends_at=excluded.trial_ends_at,updated_at=now()
  returning * into v_row;
  return v_row;
end $$;
revoke all on function public.start_trial(text) from public, anon;
grant execute on function public.start_trial(text) to authenticated;

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;
drop trigger if exists trg_org_subscriptions_updated_at on public.organization_subscriptions;
create trigger trg_org_subscriptions_updated_at before update on public.organization_subscriptions for each row execute function public.touch_updated_at();
