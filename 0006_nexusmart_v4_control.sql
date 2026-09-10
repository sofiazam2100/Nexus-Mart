-- NexusMart V4.3 Qatar — owner control, invoice sequencing, reconciliation and settings
create table if not exists public.invoice_sequences (
  branch_id uuid primary key references public.branches(id) on delete cascade,
  next_number bigint not null default 1 check(next_number > 0)
);

create table if not exists public.organization_settings (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  receipt_language text not null default 'ar-en',
  receipt_footer text not null default '',
  invoice_prefix text not null default 'INV',
  allow_negative_stock boolean not null default false,
  default_tax_profile text not null default 'standard',
  updated_at timestamptz not null default now()
);

alter table public.invoice_sequences enable row level security;
alter table public.organization_settings enable row level security;

drop policy if exists invoice_sequence_select on public.invoice_sequences;
create policy invoice_sequence_select on public.invoice_sequences for select to authenticated
using (exists (select 1 from public.branches b where b.id=branch_id and b.organization_id in (select public.my_org_ids())));

drop policy if exists settings_select on public.organization_settings;
create policy settings_select on public.organization_settings for select to authenticated
using (organization_id in (select public.my_org_ids()));

grant select on public.invoice_sequences, public.organization_settings to authenticated;
revoke all on public.invoice_sequences, public.organization_settings from anon;

create or replace function public.next_invoice_no(p_branch_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_num bigint; v_prefix text;
 v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select organization_id into v_org from public.branches where id=p_branch_id and active;
  if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;
  perform public._assert_branch_access(p_branch_id,v_org,'cashier');
  select invoice_prefix into v_prefix from public.organization_settings where organization_id=v_org;
  v_prefix:=coalesce(nullif(trim(v_prefix),''),'INV');
  insert into public.invoice_sequences(branch_id,next_number) values(p_branch_id,2)
    on conflict(branch_id) do update set next_number=public.invoice_sequences.next_number+1
    returning next_number-1 into v_num;
  return v_prefix||'-'||lpad(v_num::text,6,'0');
end; $$;
revoke all on function public.next_invoice_no(uuid) from public,anon; grant execute on function public.next_invoice_no(uuid) to authenticated;

create or replace function public.update_org_settings(
  p_receipt_language text default 'ar-en', p_receipt_footer text default '', p_invoice_prefix text default 'INV',
  p_allow_negative_stock boolean default false, p_default_tax_profile text default 'standard'
) returns public.organization_settings language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_org uuid; v_row public.organization_settings;
begin
  select organization_id into v_org from public.memberships where user_id=v_uid and active order by created_at limit 1;
  if v_org is null then raise exception 'ORG_REQUIRED'; end if;
  if public.my_role(v_org) not in ('owner','manager') then raise exception 'ROLE_REQUIRED'; end if;
  if p_receipt_language not in ('ar-en','ar-en-bn') then raise exception 'INVALID_RECEIPT_LANGUAGE'; end if;
  if coalesce(trim(p_invoice_prefix),'')='' or length(trim(p_invoice_prefix))>8 then raise exception 'INVALID_INVOICE_PREFIX'; end if;
  insert into public.organization_settings(organization_id,receipt_language,receipt_footer,invoice_prefix,allow_negative_stock,default_tax_profile)
  values(v_org,p_receipt_language,coalesce(p_receipt_footer,''),upper(trim(p_invoice_prefix)),p_allow_negative_stock,coalesce(nullif(trim(p_default_tax_profile),''),'standard'))
  on conflict(organization_id) do update set receipt_language=excluded.receipt_language,receipt_footer=excluded.receipt_footer,invoice_prefix=excluded.invoice_prefix,allow_negative_stock=excluded.allow_negative_stock,default_tax_profile=excluded.default_tax_profile,updated_at=now()
  returning * into v_row;
  return v_row;
end; $$;
revoke all on function public.update_org_settings(text,text,text,boolean,text) from public,anon; grant execute on function public.update_org_settings(text,text,text,boolean,text) to authenticated;

create or replace function public.change_member_role(p_membership_id uuid,p_role public.app_role)
returns public.memberships language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_actor public.memberships%rowtype; v_target public.memberships; v_org uuid;
begin
  select * into v_actor from public.memberships where user_id=v_uid and active order by created_at limit 1;
  if not found or v_actor.role<>'owner' then raise exception 'OWNER_REQUIRED'; end if;
  select organization_id into v_org from public.memberships where id=p_membership_id and active;
  if v_org is null or v_org<>v_actor.organization_id then raise exception 'MEMBER_NOT_FOUND'; end if;
  if p_role is null then raise exception 'INVALID_ROLE'; end if;
  if p_membership_id=v_actor.id and p_role<>'owner' then raise exception 'CANNOT_DEMOTE_SELF'; end if;
  update public.memberships set role=p_role where id=p_membership_id returning * into v_target;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(v_org,v_uid,'member.role_changed','membership',p_membership_id,jsonb_build_object('role',p_role));
  return v_target;
end; $$;
revoke all on function public.change_member_role(uuid,public.app_role) from public,anon; grant execute on function public.change_member_role(uuid,public.app_role) to authenticated;

create or replace function public.checkout_sale(
  p_branch_id uuid, p_customer_id uuid, p_discount_minor bigint, p_items jsonb, p_payments jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid:=(select auth.uid()); v_org uuid; v_sale uuid:=gen_random_uuid(); v_invoice text; v_subtotal bigint:=0; v_total bigint:=0; v_paid bigint:=0; v_due bigint:=0; v_cost bigint:=0; v_item jsonb; v_product public.products%rowtype; v_qty numeric; v_unit_price bigint; v_line bigint; v_payment jsonb; v_method public.payment_method; v_amount bigint; v_credit bigint; v_cash_register uuid; v_negative boolean:=false;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select organization_id into v_org from public.branches where id=p_branch_id and active;
  if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;
  perform public._assert_branch_access(p_branch_id,v_org,'cashier');
  select coalesce(allow_negative_stock,false) into v_negative from public.organization_settings where organization_id=v_org;
  if p_discount_minor<0 then raise exception 'INVALID_DISCOUNT'; end if;
  if jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'EMPTY_CART'; end if;
  if p_customer_id is not null and not exists(select 1 from public.customers where id=p_customer_id and organization_id=v_org and active) then raise exception 'CUSTOMER_ACCESS_DENIED'; end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty:=(v_item->>'quantity')::numeric; v_unit_price:=(v_item->>'unit_price_minor')::bigint;
    if v_qty<=0 or v_unit_price<0 then raise exception 'INVALID_ITEM'; end if;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and organization_id=v_org and (branch_id=p_branch_id or branch_id is null) and active for update;
    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
    if not v_negative and v_product.stock_qty<v_qty then raise exception 'INSUFFICIENT_STOCK'; end if;
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
  v_invoice:=public.next_invoice_no(p_branch_id);
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
  select id into v_cash_register from public.cash_registers where branch_id=p_branch_id and closed_at is null order by opened_at desc limit 1 for update;
  if v_cash_register is not null then
    insert into public.cash_movements(organization_id,branch_id,register_id,direction,amount_minor,movement_type,reference_id,created_by)
    select v_org,p_branch_id,v_cash_register,'debit',sp.amount_minor,'sale',v_sale,v_uid from public.sale_payments sp where sp.sale_id=v_sale and sp.method='cash';
  end if;
  insert into public.audit_logs(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata) values(v_org,p_branch_id,v_uid,'sale.created','sale',v_sale,jsonb_build_object('invoice_no',v_invoice,'total_minor',v_total));
  return jsonb_build_object('sale_id',v_sale,'invoice_no',v_invoice,'subtotal_minor',v_subtotal,'discount_minor',p_discount_minor,'total_minor',v_total,'paid_minor',v_paid,'due_minor',v_due,'cost_minor',v_cost);
end; $$;
revoke all on function public.checkout_sale(uuid,uuid,bigint,jsonb,jsonb) from public,anon; grant execute on function public.checkout_sale(uuid,uuid,bigint,jsonb,jsonb) to authenticated;

create or replace function public.receive_customer_payment(p_branch_id uuid,p_customer_id uuid,p_amount_minor bigint,p_method public.payment_method,p_note text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_uid uuid := (select auth.uid()); v_id uuid; v_register uuid;
begin
 select organization_id into v_org from public.branches where id=p_branch_id and active; if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;
 perform public._assert_branch_access(p_branch_id,v_org,'cashier'); if p_amount_minor<=0 then raise exception 'INVALID_AMOUNT'; end if;
 if not exists(select 1 from public.customers where id=p_customer_id and organization_id=v_org and active) then raise exception 'CUSTOMER_NOT_FOUND'; end if;
 if (select balance_minor from public.customers where id=p_customer_id) < p_amount_minor then raise exception 'PAYMENT_EXCEEDS_DUE'; end if;
 update public.customers set balance_minor=balance_minor-p_amount_minor where id=p_customer_id;
 insert into public.customer_ledger(organization_id,customer_id,direction,amount_minor,reference_type,note,created_by) values(v_org,p_customer_id,'credit',p_amount_minor,'payment',p_note,v_uid) returning id into v_id;
 if p_method='cash' then select id into v_register from public.cash_registers where branch_id=p_branch_id and closed_at is null order by opened_at desc limit 1; if v_register is not null then insert into public.cash_movements(organization_id,branch_id,register_id,direction,amount_minor,movement_type,reference_id,created_by) values(v_org,p_branch_id,v_register,'debit',p_amount_minor,'customer_payment',v_id,v_uid); end if; end if;
 return v_id;
end; $$;
revoke all on function public.receive_customer_payment(uuid,uuid,bigint,public.payment_method,text) from public,anon; grant execute on function public.receive_customer_payment(uuid,uuid,bigint,public.payment_method,text) to authenticated;

create or replace function public.pay_supplier(p_branch_id uuid,p_supplier_id uuid,p_amount_minor bigint,p_method public.payment_method,p_note text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_uid uuid := (select auth.uid()); v_id uuid; v_register uuid;
begin
 select organization_id into v_org from public.branches where id=p_branch_id and active; if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;
 perform public._assert_branch_access(p_branch_id,v_org,'cashier'); if p_amount_minor<=0 then raise exception 'INVALID_AMOUNT'; end if;
 if not exists(select 1 from public.suppliers where id=p_supplier_id and organization_id=v_org and active) then raise exception 'SUPPLIER_NOT_FOUND'; end if;
 if (select balance_minor from public.suppliers where id=p_supplier_id) < p_amount_minor then raise exception 'PAYMENT_EXCEEDS_PAYABLE'; end if;
 update public.suppliers set balance_minor=balance_minor-p_amount_minor where id=p_supplier_id;
 insert into public.supplier_ledger(organization_id,supplier_id,direction,amount_minor,reference_type,note,created_by) values(v_org,p_supplier_id,'debit',p_amount_minor,'payment',p_note,v_uid) returning id into v_id;
 if p_method='cash' then select id into v_register from public.cash_registers where branch_id=p_branch_id and closed_at is null order by opened_at desc limit 1; if v_register is not null then insert into public.cash_movements(organization_id,branch_id,register_id,direction,amount_minor,movement_type,reference_id,created_by) values(v_org,p_branch_id,v_register,'credit',p_amount_minor,'supplier_payment',v_id,v_uid); end if; end if;
 return v_id;
end; $$;
revoke all on function public.pay_supplier(uuid,uuid,bigint,public.payment_method,text) from public,anon; grant execute on function public.pay_supplier(uuid,uuid,bigint,public.payment_method,text) to authenticated;

create or replace function public.create_expense(p_branch_id uuid,p_category text,p_amount_minor bigint,p_note text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_uid uuid:=(select auth.uid()); v_id uuid; v_register uuid;
begin
 select organization_id into v_org from public.branches where id=p_branch_id and active; if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;
 perform public._assert_branch_access(p_branch_id,v_org,'manager'); if coalesce(trim(p_category),'')='' or p_amount_minor<=0 then raise exception 'INVALID_EXPENSE'; end if;
 insert into public.expenses(organization_id,branch_id,category,amount_minor,note,created_by) values(v_org,p_branch_id,trim(p_category),p_amount_minor,p_note,v_uid) returning id into v_id;
 select id into v_register from public.cash_registers where branch_id=p_branch_id and closed_at is null order by opened_at desc limit 1;
 if v_register is not null then insert into public.cash_movements(organization_id,branch_id,register_id,direction,amount_minor,movement_type,reference_id,created_by) values(v_org,p_branch_id,v_register,'credit',p_amount_minor,'expense',v_id,v_uid); end if;
 return v_id;
end; $$;
revoke all on function public.create_expense(uuid,text,bigint,text) from public,anon; grant execute on function public.create_expense(uuid,text,bigint,text) to authenticated;

create or replace function public.process_return(p_branch_id uuid,p_sale_id uuid,p_items jsonb,p_refund_method public.payment_method,p_reason text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=(select auth.uid()); v_org uuid; v_return uuid:=gen_random_uuid(); v_refund bigint:=0; v_item jsonb; v_si public.sale_items%rowtype; v_qty numeric; v_already numeric; v_refund_line bigint; v_customer uuid; v_register uuid;
begin
  select organization_id,customer_id into v_org,v_customer from public.sales where id=p_sale_id and branch_id=p_branch_id and status='posted'; if v_org is null then raise exception 'SALE_NOT_FOUND'; end if;
  perform public._assert_branch_access(p_branch_id,v_org,'manager'); if jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'EMPTY_RETURN'; end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty:=(v_item->>'quantity')::numeric; select * into v_si from public.sale_items where id=(v_item->>'sale_item_id')::uuid and sale_id=p_sale_id;
    if not found then raise exception 'SALE_ITEM_NOT_FOUND'; end if;
    select coalesce(sum(ri.quantity),0) into v_already from public.return_items ri join public.returns r on r.id=ri.return_id where ri.sale_item_id=v_si.id;
    if v_qty<=0 or v_qty>v_si.quantity-v_already then raise exception 'RETURN_QTY_EXCEEDS_REMAINING'; end if;
  end loop;
  insert into public.returns(organization_id,branch_id,sale_id,customer_id,refund_minor,refund_method,reason,created_by) values(v_org,p_branch_id,p_sale_id,v_customer,0,p_refund_method,p_reason,v_uid) returning id into v_return;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty:=(v_item->>'quantity')::numeric; select * into v_si from public.sale_items where id=(v_item->>'sale_item_id')::uuid for update; v_refund_line:=round(v_qty*v_si.unit_price_minor); v_refund:=v_refund+v_refund_line;
    insert into public.return_items(return_id,sale_item_id,quantity,refund_line_minor) values(v_return,v_si.id,v_qty,v_refund_line);
    update public.products set stock_qty=stock_qty+v_qty,updated_at=now() where id=v_si.product_id;
    insert into public.inventory_movements(organization_id,branch_id,product_id,movement_type,quantity_delta,unit_cost_minor,reference_type,reference_id,created_by) values(v_org,p_branch_id,v_si.product_id,'return',v_qty,v_si.unit_cost_minor,'return',v_return,v_uid);
  end loop;
  update public.returns set refund_minor=v_refund where id=v_return;
  if v_customer is not null and v_refund>0 then
    update public.customers set balance_minor=greatest(0,balance_minor-v_refund) where id=v_customer;
    insert into public.customer_ledger(organization_id,customer_id,direction,amount_minor,reference_type,reference_id,note,created_by) values(v_org,v_customer,'credit',v_refund,'return',v_return,'Return credit',v_uid);
  elsif v_refund>0 and p_refund_method='cash' then
    select id into v_register from public.cash_registers where branch_id=p_branch_id and closed_at is null order by opened_at desc limit 1;
    if v_register is null then raise exception 'OPEN_REGISTER_REQUIRED_FOR_CASH_REFUND'; end if;
    insert into public.cash_movements(organization_id,branch_id,register_id,direction,amount_minor,movement_type,reference_id,created_by) values(v_org,p_branch_id,v_register,'credit',v_refund,'refund',v_return,v_uid);
  end if;
  insert into public.audit_logs(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata) values(v_org,p_branch_id,v_uid,'return.created','return',v_return,jsonb_build_object('refund_minor',v_refund,'sale_id',p_sale_id,'refund_method',p_refund_method));
  return jsonb_build_object('return_id',v_return,'refund_minor',v_refund);
end; $$;
revoke all on function public.process_return(uuid,uuid,jsonb,public.payment_method,text) from public,anon; grant execute on function public.process_return(uuid,uuid,jsonb,public.payment_method,text) to authenticated;

-- Ensure a default settings row exists for each organization.
insert into public.organization_settings(organization_id)
select id from public.organizations o where not exists(select 1 from public.organization_settings s where s.organization_id=o.id);
