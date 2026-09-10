-- V4 RLS
alter table public.organizations enable row level security;
alter table public.branches enable row level security;
alter table public.memberships enable row level security;
alter table public.branch_memberships enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.sale_payments enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.customer_ledger enable row level security;
alter table public.supplier_ledger enable row level security;
alter table public.returns enable row level security;
alter table public.return_items enable row level security;
alter table public.expenses enable row level security;
alter table public.cash_registers enable row level security;
alter table public.cash_movements enable row level security;
alter table public.audit_logs enable row level security;

create or replace function public.my_org_ids()
returns setof uuid
language sql
stable
security invoker
set search_path = public
as $$
  select organization_id
  from public.memberships
  where user_id = (select auth.uid()) and active;
$$;

create or replace function public.is_org_member(p_org uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1 from public.memberships
    where organization_id = p_org
      and user_id = (select auth.uid())
      and active
  );
$$;

create or replace function public.my_role(p_org uuid)
returns public.app_role
language sql
stable
security invoker
set search_path = public
as $$
  select role from public.memberships
  where organization_id = p_org
    and user_id = (select auth.uid())
    and active
  limit 1;
$$;

create or replace function public.can_write(p_org uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select public.my_role(p_org) in ('owner','manager');
$$;

-- Read policies: every row must belong to an organization the current user belongs to.
create policy org_select on public.organizations for select to authenticated
using (id in (select public.my_org_ids()));

create policy branch_select on public.branches for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy membership_select on public.memberships for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy branch_membership_select on public.branch_memberships for select to authenticated
using (exists (
  select 1 from public.branches b
  where b.id = branch_id and b.organization_id in (select public.my_org_ids())
));

create policy categories_select on public.categories for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy products_select on public.products for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy customers_select on public.customers for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy suppliers_select on public.suppliers for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy sales_select on public.sales for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy sale_items_select on public.sale_items for select to authenticated
using (exists (
  select 1 from public.sales s
  where s.id = sale_id and s.organization_id in (select public.my_org_ids())
));

create policy sale_payments_select on public.sale_payments for select to authenticated
using (exists (
  select 1 from public.sales s
  where s.id = sale_id and s.organization_id in (select public.my_org_ids())
));

create policy inventory_select on public.inventory_movements for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy customer_ledger_select on public.customer_ledger for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy supplier_ledger_select on public.supplier_ledger for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy returns_select on public.returns for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy return_items_select on public.return_items for select to authenticated
using (exists (
  select 1 from public.returns r
  where r.id = return_id and r.organization_id in (select public.my_org_ids())
));

create policy expenses_select on public.expenses for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy cash_register_select on public.cash_registers for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy cash_movements_select on public.cash_movements for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy audit_select on public.audit_logs for select to authenticated
using (organization_id in (select public.my_org_ids()));

-- Direct financial writes are deliberately restricted.
-- Normal sales/purchases/returns/payments must use server-side database functions.
revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;

grant select on public.organizations, public.branches, public.memberships, public.branch_memberships,
  public.categories, public.products, public.customers, public.suppliers, public.sales, public.sale_items,
  public.sale_payments, public.inventory_movements, public.customer_ledger, public.supplier_ledger,
  public.returns, public.return_items, public.expenses, public.cash_registers, public.cash_movements,
  public.audit_logs to authenticated;

-- Critical mutation functions are granted separately in migration 0003.
