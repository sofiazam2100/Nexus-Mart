-- NexusMart V4.2 Qatar Operations Pack
-- All money values are QAR minor units (dirhams).
-- Mutation functions are tightly scoped and explicitly revoke EXECUTE from PUBLIC/anon.

create table if not exists public.purchases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  supplier_id uuid not null references public.suppliers(id),
  invoice_no text not null,
  subtotal_minor bigint not null check(subtotal_minor >= 0),
  paid_minor bigint not null default 0 check(paid_minor >= 0),
  due_minor bigint not null default 0 check(due_minor >= 0),
  status public.document_status not null default 'posted',
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(branch_id, invoice_no)
);

create table if not exists public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.purchases(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity numeric(14,3) not null check(quantity > 0),
  unit_cost_minor bigint not null check(unit_cost_minor >= 0),
  line_total_minor bigint not null check(line_total_minor >= 0)
);

alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;

create policy purchases_select on public.purchases for select to authenticated
using (organization_id in (select public.my_org_ids()));
create policy purchase_items_select on public.purchase_items for select to authenticated
using (exists (select 1 from public.purchases p where p.id=purchase_id and p.organization_id in (select public.my_org_ids())));

grant select on public.purchases, public.purchase_items to authenticated;

-- Branch-local invoice counter. One row per branch/year/month.
create table if not exists public.invoice_counters (
  branch_id uuid not null references public.branches(id) on delete cascade,
  period_key text not null,
  last_number bigint not null default 0,
  primary key(branch_id, period_key)
);
alter table public.invoice_counters enable row level security;
create policy invoice_counters_select on public.invoice_counters for select to authenticated
using (branch_id in (select b.id from public.branches b where b.organization_id in (select public.my_org_ids())));
grant select on public.invoice_counters to authenticated;

create or replace function public._assert_branch_access(p_branch uuid, p_org uuid, p_min_role public.app_role default 'cashier')
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_role public.app_role;
begin
  select m.role into v_role
  from public.memberships m
  join public.branch_memberships bm on bm.membership_id=m.id
  where m.user_id=(select auth.uid()) and m.organization_id=p_org and m.active and bm.branch_id=p_branch;
  if v_role is null then raise exception 'BRANCH_ACCESS_DENIED'; end if;
  if p_min_role in ('owner','manager') and v_role not in ('owner','manager') then raise exception 'MANAGER_PERMISSION_REQUIRED'; end if;
end;
$$;
revoke all on function public._assert_branch_access(uuid,uuid,public.app_role) from public, anon, authenticated;

create or replace function public.create_category(
  p_name_en text, p_name_ar text default '', p_name_bn text default ''
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_id uuid;
begin
  select organization_id into v_org from public.memberships where user_id=(select auth.uid()) and active limit 1;
  if v_org is null then raise exception 'ORG_REQUIRED'; end if;
  perform public._assert_branch_access((select b.id from public.branches b where b.organization_id=v_org and b.active order by b.created_at limit 1),v_org,'manager');
  if coalesce(trim(p_name_en),'')='' then raise exception 'CATEGORY_NAME_REQUIRED'; end if;
  insert into public.categories(organization_id,name_en,name_ar,name_bn) values(v_org,trim(p_name_en),coalesce(p_name_ar,''),coalesce(p_name_bn,'')) returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.create_category(text,text,text) from public, anon; grant execute on function public.create_category(text,text,text) to authenticated;

create or replace function public.upsert_product(
  p_product_id uuid default null, p_branch_id uuid default null, p_category_id uuid default null,
  p_sku text default null, p_barcode text default null, p_name_en text default '', p_name_ar text default '', p_name_bn text default '',
  p_cost_minor bigint default 0, p_selling_minor bigint default 0, p_reorder_level numeric default 0, p_tax_profile text default 'standard'
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'AUTH_REQUIRED'; end if;
  if coalesce(trim(p_name_en),'')='' then raise exception 'PRODUCT_NAME_REQUIRED'; end if;
  if p_cost_minor<0 or p_selling_minor<0 or p_reorder_level<0 then raise exception 'INVALID_PRODUCT_VALUES'; end if;
  select organization_id into v_org from public.memberships where user_id=(select auth.uid()) and active limit 1;
  if v_org is null then raise exception 'ORG_REQUIRED'; end if;
  if p_branch_id is not null then perform public._assert_branch_access(p_branch_id,v_org,'manager'); end if;
  if p_category_id is not null and not exists(select 1 from public.categories where id=p_category_id and organization_id=v_org) then raise exception 'CATEGORY_ACCESS_DENIED'; end if;
  if p_product_id is null then
    if p_barcode is not null and exists(select 1 from public.products where organization_id=v_org and barcode=p_barcode) then raise exception 'BARCODE_EXISTS'; end if;
    insert into public.products(organization_id,branch_id,category_id,sku,barcode,name_en,name_ar,name_bn,cost_minor,selling_minor,reorder_level,tax_profile)
    values(v_org,p_branch_id,p_category_id,nullif(trim(p_sku),''),nullif(trim(p_barcode),''),trim(p_name_en),coalesce(p_name_ar,''),coalesce(p_name_bn,''),p_cost_minor,p_selling_minor,p_reorder_level,coalesce(p_tax_profile,'standard')) returning id into v_id;
  else
    if not exists(select 1 from public.products where id=p_product_id and organization_id=v_org) then raise exception 'PRODUCT_NOT_FOUND'; end if;
    if p_barcode is not null and exists(select 1 from public.products where organization_id=v_org and barcode=p_barcode and id<>p_product_id) then raise exception 'BARCODE_EXISTS'; end if;
    update public.products set branch_id=p_branch_id,category_id=p_category_id,sku=nullif(trim(p_sku),''),barcode=nullif(trim(p_barcode),''),name_en=trim(p_name_en),name_ar=coalesce(p_name_ar,''),name_bn=coalesce(p_name_bn,''),cost_minor=p_cost_minor,selling_minor=p_selling_minor,reorder_level=p_reorder_level,tax_profile=coalesce(p_tax_profile,'standard'),updated_at=now() where id=p_product_id returning id into v_id;
  end if;
  return v_id;
end; $$;
revoke all on function public.upsert_product(uuid,uuid,uuid,text,text,text,text,text,bigint,bigint,numeric,text) from public, anon; grant execute on function public.upsert_product(uuid,uuid,uuid,text,text,text,text,text,bigint,bigint,numeric,text) to authenticated;

create or replace function public.adjust_stock(p_branch_id uuid,p_product_id uuid,p_quantity_delta numeric,p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_stock numeric; v_cost bigint; v_uid uuid := (select auth.uid());
begin
  select organization_id into v_org from public.branches where id=p_branch_id and active;
  if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;
  perform public._assert_branch_access(p_branch_id,v_org,'manager');
  if p_quantity_delta=0 then raise exception 'ZERO_ADJUSTMENT'; end if;
  select stock_qty,cost_minor into v_stock,v_cost from public.products where id=p_product_id and organization_id=v_org and (branch_id=p_branch_id or branch_id is null) and active for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
  if v_stock+p_quantity_delta<0 then raise exception 'NEGATIVE_STOCK'; end if;
  update public.products set stock_qty=stock_qty+p_quantity_delta,updated_at=now() where id=p_product_id;
  insert into public.inventory_movements(organization_id,branch_id,product_id,movement_type,quantity_delta,unit_cost_minor,reference_type,created_by)
  values(v_org,p_branch_id,p_product_id,'adjustment',p_quantity_delta,v_cost,'manual_adjustment',v_uid);
  insert into public.audit_logs(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(v_org,p_branch_id,v_uid,'inventory.adjusted','product',p_product_id,jsonb_build_object('delta',p_quantity_delta,'reason',p_reason));
  return jsonb_build_object('product_id',p_product_id,'stock_qty',v_stock+p_quantity_delta);
end; $$;
revoke all on function public.adjust_stock(uuid,uuid,numeric,text) from public, anon; grant execute on function public.adjust_stock(uuid,uuid,numeric,text) to authenticated;

create or replace function public.create_customer(p_name text,p_phone text default null,p_whatsapp text default null,p_credit_limit_minor bigint default 0,p_opening_balance_minor bigint default 0)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_id uuid; v_uid uuid := (select auth.uid());
begin
  select organization_id into v_org from public.memberships where user_id=v_uid and active limit 1;
  if v_org is null then raise exception 'ORG_REQUIRED'; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'CUSTOMER_NAME_REQUIRED'; end if;
  if p_credit_limit_minor<0 or p_opening_balance_minor<0 then raise exception 'INVALID_BALANCE'; end if;
  insert into public.customers(organization_id,name,phone,whatsapp,credit_limit_minor,balance_minor,opening_balance_minor) values(v_org,trim(p_name),p_phone,p_whatsapp,p_credit_limit_minor,p_opening_balance_minor,p_opening_balance_minor) returning id into v_id;
  if p_opening_balance_minor>0 then insert into public.customer_ledger(organization_id,customer_id,direction,amount_minor,reference_type,note,created_by) values(v_org,v_id,'debit',p_opening_balance_minor,'opening_balance','Opening balance',v_uid); end if;
  return v_id;
end; $$;
revoke all on function public.create_customer(text,text,text,bigint,bigint) from public, anon; grant execute on function public.create_customer(text,text,text,bigint,bigint) to authenticated;

create or replace function public.receive_customer_payment(p_branch_id uuid,p_customer_id uuid,p_amount_minor bigint,p_method public.payment_method,p_note text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_uid uuid := (select auth.uid()); v_id uuid;
begin
  select organization_id into v_org from public.branches where id=p_branch_id and active;
  if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;
  perform public._assert_branch_access(p_branch_id,v_org,'cashier');
  if p_amount_minor<=0 then raise exception 'INVALID_AMOUNT'; end if;
  if not exists(select 1 from public.customers where id=p_customer_id and organization_id=v_org and active) then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  if (select balance_minor from public.customers where id=p_customer_id) < p_amount_minor then raise exception 'PAYMENT_EXCEEDS_DUE'; end if;
  update public.customers set balance_minor=balance_minor-p_amount_minor where id=p_customer_id;
  insert into public.customer_ledger(organization_id,customer_id,direction,amount_minor,reference_type,note,created_by) values(v_org,p_customer_id,'credit',p_amount_minor,'payment',p_note,v_uid) returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.receive_customer_payment(uuid,uuid,bigint,public.payment_method,text) from public, anon; grant execute on function public.receive_customer_payment(uuid,uuid,bigint,public.payment_method,text) to authenticated;

create or replace function public.create_supplier(p_name text,p_phone text default null,p_whatsapp text default null,p_opening_balance_minor bigint default 0)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_id uuid; v_uid uuid := (select auth.uid());
begin
  select organization_id into v_org from public.memberships where user_id=v_uid and active limit 1;
  if v_org is null then raise exception 'ORG_REQUIRED'; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'SUPPLIER_NAME_REQUIRED'; end if;
  if p_opening_balance_minor<0 then raise exception 'INVALID_BALANCE'; end if;
  insert into public.suppliers(organization_id,name,phone,whatsapp,opening_balance_minor,balance_minor) values(v_org,trim(p_name),p_phone,p_whatsapp,p_opening_balance_minor,p_opening_balance_minor) returning id into v_id;
  if p_opening_balance_minor>0 then insert into public.supplier_ledger(organization_id,supplier_id,direction,amount_minor,reference_type,note,created_by) values(v_org,v_id,'credit',p_opening_balance_minor,'opening_balance','Opening payable',v_uid); end if;
  return v_id;
end; $$;
revoke all on function public.create_supplier(text,text,text,bigint) from public, anon; grant execute on function public.create_supplier(text,text,text,bigint) to authenticated;

create or replace function public.pay_supplier(p_branch_id uuid,p_supplier_id uuid,p_amount_minor bigint,p_method public.payment_method,p_note text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_uid uuid := (select auth.uid()); v_id uuid;
begin
  select organization_id into v_org from public.branches where id=p_branch_id and active;
  if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;
  perform public._assert_branch_access(p_branch_id,v_org,'cashier');
  if p_amount_minor<=0 then raise exception 'INVALID_AMOUNT'; end if;
  if not exists(select 1 from public.suppliers where id=p_supplier_id and organization_id=v_org and active) then raise exception 'SUPPLIER_NOT_FOUND'; end if;
  if (select balance_minor from public.suppliers where id=p_supplier_id) < p_amount_minor then raise exception 'PAYMENT_EXCEEDS_PAYABLE'; end if;
  update public.suppliers set balance_minor=balance_minor-p_amount_minor where id=p_supplier_id;
  insert into public.supplier_ledger(organization_id,supplier_id,direction,amount_minor,reference_type,note,created_by) values(v_org,p_supplier_id,'debit',p_amount_minor,'payment',p_note,v_uid) returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.pay_supplier(uuid,uuid,bigint,public.payment_method,text) from public, anon; grant execute on function public.pay_supplier(uuid,uuid,bigint,public.payment_method,text) to authenticated;

create or replace function public.create_purchase(p_branch_id uuid,p_supplier_id uuid,p_items jsonb,p_paid_minor bigint default 0)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_org uuid; v_purchase uuid:=gen_random_uuid(); v_subtotal bigint:=0; v_due bigint; v_item jsonb; v_product public.products%rowtype; v_qty numeric; v_cost bigint; v_line bigint; v_invoice text;
begin
  select organization_id into v_org from public.branches where id=p_branch_id and active;
  if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;
  perform public._assert_branch_access(p_branch_id,v_org,'manager');
  if not exists(select 1 from public.suppliers where id=p_supplier_id and organization_id=v_org and active) then raise exception 'SUPPLIER_NOT_FOUND'; end if;
  if jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'EMPTY_PURCHASE'; end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty:=(v_item->>'quantity')::numeric; v_cost:=(v_item->>'unit_cost_minor')::bigint;
    if v_qty<=0 or v_cost<0 then raise exception 'INVALID_PURCHASE_ITEM'; end if;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and organization_id=v_org and (branch_id=p_branch_id or branch_id is null) and active for update;
    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
    v_line:=round(v_qty*v_cost); v_subtotal:=v_subtotal+v_line;
  end loop;
  if p_paid_minor<0 or p_paid_minor>v_subtotal then raise exception 'INVALID_PURCHASE_PAYMENT'; end if;
  v_due:=v_subtotal-p_paid_minor;
  v_invoice:='PUR-'||to_char(now() at time zone 'Asia/Qatar','YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(v_purchase::text,'-',''),1,6));
  insert into public.purchases(id,organization_id,branch_id,supplier_id,invoice_no,subtotal_minor,paid_minor,due_minor,created_by) values(v_purchase,v_org,p_branch_id,p_supplier_id,v_invoice,v_subtotal,p_paid_minor,v_due,v_uid);
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty:=(v_item->>'quantity')::numeric; v_cost:=(v_item->>'unit_cost_minor')::bigint;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid for update;
    v_line:=round(v_qty*v_cost);
    insert into public.purchase_items(purchase_id,product_id,quantity,unit_cost_minor,line_total_minor) values(v_purchase,v_product.id,v_qty,v_cost,v_line);
    update public.products set stock_qty=stock_qty+v_qty,cost_minor=case when stock_qty+v_qty=0 then v_cost else round(((stock_qty*cost_minor)+(v_qty*v_cost))/(stock_qty+v_qty)) end,updated_at=now() where id=v_product.id;
    insert into public.inventory_movements(organization_id,branch_id,product_id,movement_type,quantity_delta,unit_cost_minor,reference_type,reference_id,created_by) values(v_org,p_branch_id,v_product.id,'purchase',v_qty,v_cost,'purchase',v_purchase,v_uid);
  end loop;
  if v_due>0 then update public.suppliers set balance_minor=balance_minor+v_due where id=p_supplier_id; insert into public.supplier_ledger(organization_id,supplier_id,direction,amount_minor,reference_type,reference_id,created_by) values(v_org,p_supplier_id,'credit',v_due,'purchase',v_purchase,v_uid); end if;
  return jsonb_build_object('purchase_id',v_purchase,'invoice_no',v_invoice,'subtotal_minor',v_subtotal,'paid_minor',p_paid_minor,'due_minor',v_due);
end; $$;
revoke all on function public.create_purchase(uuid,uuid,jsonb,bigint) from public, anon; grant execute on function public.create_purchase(uuid,uuid,jsonb,bigint) to authenticated;

create or replace function public.create_expense(p_branch_id uuid,p_category text,p_amount_minor bigint,p_note text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_uid uuid:=(select auth.uid()); v_id uuid;
begin
  select organization_id into v_org from public.branches where id=p_branch_id and active;
  if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;
  perform public._assert_branch_access(p_branch_id,v_org,'manager');
  if coalesce(trim(p_category),'')='' or p_amount_minor<=0 then raise exception 'INVALID_EXPENSE'; end if;
  insert into public.expenses(organization_id,branch_id,category,amount_minor,note,created_by) values(v_org,p_branch_id,trim(p_category),p_amount_minor,p_note,v_uid) returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.create_expense(uuid,text,bigint,text) from public, anon; grant execute on function public.create_expense(uuid,text,bigint,text) to authenticated;

create or replace function public.open_cash_register(p_branch_id uuid,p_opening_cash_minor bigint)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_uid uuid:=(select auth.uid()); v_id uuid;
begin
  select organization_id into v_org from public.branches where id=p_branch_id and active;
  if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;
  perform public._assert_branch_access(p_branch_id,v_org,'cashier');
  if p_opening_cash_minor<0 then raise exception 'INVALID_OPENING_CASH'; end if;
  if exists(select 1 from public.cash_registers where branch_id=p_branch_id and closed_at is null) then raise exception 'REGISTER_ALREADY_OPEN'; end if;
  insert into public.cash_registers(organization_id,branch_id,opened_by,opening_cash_minor) values(v_org,p_branch_id,v_uid,p_opening_cash_minor) returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.open_cash_register(uuid,bigint) from public, anon; grant execute on function public.open_cash_register(uuid,bigint) to authenticated;

create or replace function public.close_cash_register(p_register_id uuid,p_closing_cash_minor bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.cash_registers%rowtype; v_expected bigint; v_uid uuid:=(select auth.uid()); v_variance bigint;
begin
  select * into r from public.cash_registers where id=p_register_id for update;
  if not found then raise exception 'REGISTER_NOT_FOUND'; end if;
  perform public._assert_branch_access(r.branch_id,r.organization_id,'manager');
  if r.closed_at is not null then raise exception 'REGISTER_ALREADY_CLOSED'; end if;
  if p_closing_cash_minor<0 then raise exception 'INVALID_CLOSING_CASH'; end if;
  select r.opening_cash_minor + coalesce(sum(case when cm.direction='debit' then cm.amount_minor else -cm.amount_minor end),0) into v_expected from public.cash_movements cm where cm.register_id=r.id;
  v_variance:=p_closing_cash_minor-v_expected;
  update public.cash_registers set closing_cash_minor=p_closing_cash_minor,expected_cash_minor=v_expected,variance_minor=v_variance,closed_at=now() where id=r.id;
  return jsonb_build_object('register_id',r.id,'expected_cash_minor',v_expected,'closing_cash_minor',p_closing_cash_minor,'variance_minor',v_variance);
end; $$;
revoke all on function public.close_cash_register(uuid,bigint) from public, anon; grant execute on function public.close_cash_register(uuid,bigint) to authenticated;

-- Improve checkout: customer credit-limit enforcement and customer ownership check before posting.
create or replace function public.checkout_sale(
  p_branch_id uuid, p_customer_id uuid, p_discount_minor bigint, p_items jsonb, p_payments jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid:=(select auth.uid()); v_org uuid; v_sale uuid:=gen_random_uuid(); v_invoice text; v_subtotal bigint:=0; v_total bigint:=0; v_paid bigint:=0; v_due bigint:=0; v_cost bigint:=0; v_item jsonb; v_product public.products%rowtype; v_qty numeric; v_unit_price bigint; v_line bigint; v_payment jsonb; v_method public.payment_method; v_amount bigint; v_credit bigint;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select organization_id into v_org from public.branches where id=p_branch_id and active;
  if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;
  perform public._assert_branch_access(p_branch_id,v_org,'cashier');
  if p_discount_minor<0 then raise exception 'INVALID_DISCOUNT'; end if;
  if jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'EMPTY_CART'; end if;
  if p_customer_id is not null and not exists(select 1 from public.customers where id=p_customer_id and organization_id=v_org and active) then raise exception 'CUSTOMER_ACCESS_DENIED'; end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty:=(v_item->>'quantity')::numeric; v_unit_price:=(v_item->>'unit_price_minor')::bigint;
    if v_qty<=0 or v_unit_price<0 then raise exception 'INVALID_ITEM'; end if;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and organization_id=v_org and (branch_id=p_branch_id or branch_id is null) and active for update;
    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
    if v_product.stock_qty<v_qty then raise exception 'INSUFFICIENT_STOCK'; end if;
    v_line:=round(v_qty*v_unit_price); v_subtotal:=v_subtotal+v_line; v_cost:=v_cost+round(v_qty*v_product.cost_minor);
  end loop;
  if p_discount_minor>v_subtotal then raise exception 'DISCOUNT_EXCEEDS_SUBTOTAL'; end if;
  v_total:=v_subtotal-p_discount_minor;
  for v_payment in select * from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb)) loop
    v_method:=(v_payment->>'method')::public.payment_method; v_amount:=(v_payment->>'amount_minor')::bigint;
    if v_amount<=0 then raise exception 'INVALID_PAYMENT'; end if; v_paid:=v_paid+v_amount;
  end loop;
  if v_paid>v_total then raise exception 'PAYMENT_EXCEEDS_TOTAL'; end if;
  v_due:=v_total-v_paid;
  if p_customer_id is null and v_due>0 then raise exception 'CUSTOMER_REQUIRED_FOR_DUE'; end if;
  if p_customer_id is not null then select credit_limit_minor,balance_minor into v_credit,v_amount from public.customers where id=p_customer_id for update; if v_due>0 and v_credit>0 and v_amount+v_due>v_credit then raise exception 'CREDIT_LIMIT_EXCEEDED'; end if; end if;
  v_invoice:='INV-'||to_char(now() at time zone 'Asia/Qatar','YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(v_sale::text,'-',''),1,6));
  insert into public.sales(id,organization_id,branch_id,invoice_no,customer_id,cashier_user_id,subtotal_minor,discount_minor,tax_minor,total_minor,cost_minor,paid_minor,due_minor) values(v_sale,v_org,p_branch_id,v_invoice,p_customer_id,v_uid,v_subtotal,p_discount_minor,0,v_total,v_cost,v_paid,v_due);
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty:=(v_item->>'quantity')::numeric; v_unit_price:=(v_item->>'unit_price_minor')::bigint;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid for update; v_line:=round(v_qty*v_unit_price);
    insert into public.sale_items(sale_id,product_id,quantity,unit_price_minor,unit_cost_minor,line_total_minor) values(v_sale,v_product.id,v_qty,v_unit_price,v_product.cost_minor,v_line);
    update public.products set stock_qty=stock_qty-v_qty,updated_at=now() where id=v_product.id;
    insert into public.inventory_movements(organization_id,branch_id,product_id,movement_type,quantity_delta,unit_cost_minor,reference_type,reference_id,created_by) values(v_org,p_branch_id,v_product.id,'sale',-v_qty,v_product.cost_minor,'sale',v_sale,v_uid);
  end loop;
  for v_payment in select * from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb)) loop insert into public.sale_payments(sale_id,method,amount_minor) values(v_sale,(v_payment->>'method')::public.payment_method,(v_payment->>'amount_minor')::bigint); end loop;
  if p_customer_id is not null and v_due>0 then update public.customers set balance_minor=balance_minor+v_due where id=p_customer_id; insert into public.customer_ledger(organization_id,customer_id,direction,amount_minor,reference_type,reference_id,created_by) values(v_org,p_customer_id,'debit',v_due,'sale',v_sale,v_uid); end if;
  -- If a register is open, mirror cash payments into the register ledger.
  insert into public.cash_movements(organization_id,branch_id,register_id,direction,amount_minor,movement_type,reference_id,created_by)
  select v_org,p_branch_id,cr.id,'debit',sp.amount_minor,'sale',v_sale,v_uid
  from public.cash_registers cr join public.sale_payments sp on sp.sale_id=v_sale
  where cr.branch_id=p_branch_id and cr.closed_at is null and sp.method='cash';
  insert into public.audit_logs(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata) values(v_org,p_branch_id,v_uid,'sale.created','sale',v_sale,jsonb_build_object('invoice_no',v_invoice,'total_minor',v_total));
  return jsonb_build_object('sale_id',v_sale,'invoice_no',v_invoice,'subtotal_minor',v_subtotal,'discount_minor',p_discount_minor,'total_minor',v_total,'paid_minor',v_paid,'due_minor',v_due,'cost_minor',v_cost);
end; $$;
revoke all on function public.checkout_sale(uuid,uuid,bigint,jsonb,jsonb) from public, anon; grant execute on function public.checkout_sale(uuid,uuid,bigint,jsonb,jsonb) to authenticated;

create or replace function public.process_return(p_branch_id uuid,p_sale_id uuid,p_items jsonb,p_refund_method public.payment_method,p_reason text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=(select auth.uid()); v_org uuid; v_return uuid:=gen_random_uuid(); v_refund bigint:=0; v_item jsonb; v_si public.sale_items%rowtype; v_qty numeric; v_already numeric; v_line bigint; v_refund_line bigint; v_customer uuid;
begin
  select organization_id,customer_id into v_org,v_customer from public.sales where id=p_sale_id and branch_id=p_branch_id and status='posted';
  if v_org is null then raise exception 'SALE_NOT_FOUND'; end if;
  perform public._assert_branch_access(p_branch_id,v_org,'manager');
  if jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'EMPTY_RETURN'; end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty:=(v_item->>'quantity')::numeric;
    select * into v_si from public.sale_items where id=(v_item->>'sale_item_id')::uuid and sale_id=p_sale_id;
    if not found then raise exception 'SALE_ITEM_NOT_FOUND'; end if;
    select coalesce(sum(ri.quantity),0) into v_already from public.return_items ri join public.returns r on r.id=ri.return_id where ri.sale_item_id=v_si.id;
    if v_qty<=0 or v_qty>v_si.quantity-v_already then raise exception 'RETURN_QTY_EXCEEDS_REMAINING'; end if;
  end loop;
  insert into public.returns(organization_id,branch_id,sale_id,customer_id,refund_minor,refund_method,reason,created_by) values(v_org,p_branch_id,p_sale_id,v_customer,0,p_refund_method,p_reason,v_uid) returning id into v_return;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty:=(v_item->>'quantity')::numeric; select * into v_si from public.sale_items where id=(v_item->>'sale_item_id')::uuid for update; v_line:=round(v_qty*v_si.unit_price_minor); v_refund_line:=v_line; v_refund:=v_refund+v_refund_line;
    insert into public.return_items(return_id,sale_item_id,quantity,refund_line_minor) values(v_return,v_si.id,v_qty,v_refund_line);
    update public.products set stock_qty=stock_qty+v_qty,updated_at=now() where id=v_si.product_id;
    insert into public.inventory_movements(organization_id,branch_id,product_id,movement_type,quantity_delta,unit_cost_minor,reference_type,reference_id,created_by) values(v_org,p_branch_id,v_si.product_id,'return',v_qty,v_si.unit_cost_minor,'return',v_return,v_uid);
  end loop;
  update public.returns set refund_minor=v_refund where id=v_return;
  if v_customer is not null and v_refund>0 then
    update public.customers set balance_minor=greatest(0,balance_minor-v_refund) where id=v_customer;
    insert into public.customer_ledger(organization_id,customer_id,direction,amount_minor,reference_type,reference_id,note,created_by) values(v_org,v_customer,'credit',v_refund,'return',v_return,'Return credit',v_uid);
  end if;
  insert into public.audit_logs(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata) values(v_org,p_branch_id,v_uid,'return.created','return',v_return,jsonb_build_object('refund_minor',v_refund,'sale_id',p_sale_id));
  return jsonb_build_object('return_id',v_return,'refund_minor',v_refund);
end; $$;
revoke all on function public.process_return(uuid,uuid,jsonb,public.payment_method,text) from public, anon; grant execute on function public.process_return(uuid,uuid,jsonb,public.payment_method,text) to authenticated;
