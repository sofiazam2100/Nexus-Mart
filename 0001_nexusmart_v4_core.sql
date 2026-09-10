-- NexusMart V4 Qatar — core schema
-- Money is stored in minor units: 1 QAR = 100 dirhams.
create extension if not exists pgcrypto;

create type public.app_role as enum ('owner','manager','cashier','accountant','inventory');
create type public.payment_method as enum ('cash','card','bank_transfer','other');
create type public.document_status as enum ('draft','posted','voided');
create type public.ledger_direction as enum ('debit','credit');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name_en text not null,
  name_ar text not null default '',
  name_bn text not null default '',
  cr_number text,
  phone text,
  whatsapp text,
  address text,
  country_code text not null default 'QA',
  currency text not null default 'QAR',
  timezone text not null default 'Asia/Qatar',
  created_at timestamptz not null default now()
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  code text not null,
  address text,
  phone text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(organization_id, code)
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null default 'cashier',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(organization_id, user_id)
);

create table public.branch_memberships (
  membership_id uuid not null references public.memberships(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  primary key(membership_id, branch_id)
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name_en text not null,
  name_ar text not null default '',
  name_bn text not null default '',
  active boolean not null default true
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete restrict,
  category_id uuid references public.categories(id) on delete set null,
  sku text,
  barcode text,
  name_en text not null,
  name_ar text not null default '',
  name_bn text not null default '',
  cost_minor bigint not null default 0 check(cost_minor >= 0),
  selling_minor bigint not null default 0 check(selling_minor >= 0),
  stock_qty numeric(14,3) not null default 0 check(stock_qty >= 0),
  reorder_level numeric(14,3) not null default 0 check(reorder_level >= 0),
  tax_profile text not null default 'standard',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id, barcode)
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  phone text,
  whatsapp text,
  opening_balance_minor bigint not null default 0,
  credit_limit_minor bigint not null default 0,
  balance_minor bigint not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  phone text,
  whatsapp text,
  opening_balance_minor bigint not null default 0,
  balance_minor bigint not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  invoice_no text not null,
  customer_id uuid references public.customers(id),
  cashier_user_id uuid not null references auth.users(id),
  subtotal_minor bigint not null check(subtotal_minor >= 0),
  discount_minor bigint not null default 0 check(discount_minor >= 0),
  tax_minor bigint not null default 0 check(tax_minor >= 0),
  total_minor bigint not null check(total_minor >= 0),
  cost_minor bigint not null default 0 check(cost_minor >= 0),
  paid_minor bigint not null default 0 check(paid_minor >= 0),
  due_minor bigint not null default 0 check(due_minor >= 0),
  status public.document_status not null default 'posted',
  created_at timestamptz not null default now(),
  unique(branch_id, invoice_no)
);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity numeric(14,3) not null check(quantity > 0),
  unit_price_minor bigint not null check(unit_price_minor >= 0),
  unit_cost_minor bigint not null check(unit_cost_minor >= 0),
  line_total_minor bigint not null check(line_total_minor >= 0)
);

create table public.sale_payments (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  method public.payment_method not null,
  amount_minor bigint not null check(amount_minor > 0)
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  product_id uuid not null references public.products(id),
  movement_type text not null,
  quantity_delta numeric(14,3) not null,
  unit_cost_minor bigint not null default 0,
  reference_type text,
  reference_id uuid,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.customer_ledger (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  direction public.ledger_direction not null,
  amount_minor bigint not null check(amount_minor > 0),
  reference_type text,
  reference_id uuid,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.supplier_ledger (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  direction public.ledger_direction not null,
  amount_minor bigint not null check(amount_minor > 0),
  reference_type text,
  reference_id uuid,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.returns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  sale_id uuid not null references public.sales(id),
  customer_id uuid references public.customers(id),
  refund_minor bigint not null check(refund_minor >= 0),
  refund_method public.payment_method,
  reason text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.return_items (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references public.returns(id) on delete cascade,
  sale_item_id uuid not null references public.sale_items(id),
  quantity numeric(14,3) not null check(quantity > 0),
  refund_line_minor bigint not null check(refund_line_minor >= 0)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  category text not null,
  amount_minor bigint not null check(amount_minor > 0),
  note text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.cash_registers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  opened_by uuid not null references auth.users(id),
  opening_cash_minor bigint not null default 0 check(opening_cash_minor >= 0),
  closing_cash_minor bigint,
  expected_cash_minor bigint,
  variance_minor bigint,
  opened_at timestamptz not null default now(),
  closed_at timestamptz
);

create table public.cash_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  register_id uuid not null references public.cash_registers(id),
  direction public.ledger_direction not null,
  amount_minor bigint not null check(amount_minor > 0),
  movement_type text not null,
  reference_id uuid,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id),
  actor_user_id uuid references auth.users(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index memberships_user_idx on public.memberships(user_id);
create index branch_memberships_branch_idx on public.branch_memberships(branch_id);
create index products_org_branch_idx on public.products(organization_id, branch_id);
create index products_barcode_idx on public.products(organization_id, barcode);
create index sales_org_branch_date_idx on public.sales(organization_id, branch_id, created_at desc);
create index sale_items_sale_idx on public.sale_items(sale_id);
create index inventory_product_date_idx on public.inventory_movements(product_id, created_at desc);
create index customer_ledger_customer_date_idx on public.customer_ledger(customer_id, created_at desc);
create index supplier_ledger_supplier_date_idx on public.supplier_ledger(supplier_id, created_at desc);
create index audit_org_date_idx on public.audit_logs(organization_id, created_at desc);
