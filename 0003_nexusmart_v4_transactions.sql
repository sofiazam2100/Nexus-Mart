-- NexusMart V4 — secure financial mutations
-- SECURITY DEFINER is used only for tightly-scoped transactional functions.
-- search_path is fixed and every function checks auth + organization/branch membership.

create or replace function public.create_organization(
  p_name_en text,
  p_name_ar text default '',
  p_name_bn text default '',
  p_cr_number text default null,
  p_phone text default null,
  p_whatsapp text default null,
  p_branch_name text default 'Main Branch',
  p_branch_code text default 'MAIN'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid := gen_random_uuid();
  v_branch uuid := gen_random_uuid();
  v_uid uuid := (select auth.uid());
  v_membership uuid := gen_random_uuid();
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if coalesce(trim(p_name_en),'') = '' then raise exception 'BUSINESS_NAME_REQUIRED'; end if;

  insert into public.organizations(id,name_en,name_ar,name_bn,cr_number,phone,whatsapp)
  values(v_org,trim(p_name_en),coalesce(p_name_ar,''),coalesce(p_name_bn,''),
         p_cr_number,p_phone,p_whatsapp);

  insert into public.branches(id,organization_id,name,code)
  values(v_branch,v_org,coalesce(nullif(trim(p_branch_name),''),'Main Branch'),
         upper(coalesce(nullif(trim(p_branch_code),''),'MAIN')));

  insert into public.memberships(id,organization_id,user_id,role)
  values(v_membership,v_org,v_uid,'owner');

  insert into public.branch_memberships(membership_id,branch_id)
  values(v_membership,v_branch);

  return jsonb_build_object('organization_id',v_org,'branch_id',v_branch);
end;
$$;

revoke all on function public.create_organization(text,text,text,text,text,text,text,text) from public, anon;
grant execute on function public.create_organization(text,text,text,text,text,text,text,text) to authenticated;


create or replace function public.checkout_sale(
  p_branch_id uuid,
  p_customer_id uuid,
  p_discount_minor bigint,
  p_items jsonb,
  p_payments jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_org uuid;
  v_sale uuid := gen_random_uuid();
  v_invoice text;
  v_subtotal bigint := 0;
  v_total bigint := 0;
  v_paid bigint := 0;
  v_due bigint := 0;
  v_cost bigint := 0;
  v_item jsonb;
  v_product public.products%rowtype;
  v_qty numeric;
  v_unit_price bigint;
  v_line bigint;
  v_payment jsonb;
  v_method public.payment_method;
  v_amount bigint;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select organization_id into v_org
  from public.branches b
  where b.id = p_branch_id and b.active;

  if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;

  if not exists (
    select 1
    from public.memberships m
    join public.branch_memberships bm on bm.membership_id=m.id
    where m.user_id=v_uid and m.organization_id=v_org and m.active
      and bm.branch_id=p_branch_id
  ) then raise exception 'BRANCH_ACCESS_DENIED'; end if;

  if p_discount_minor < 0 then raise exception 'INVALID_DISCOUNT'; end if;
  if jsonb_array_length(coalesce(p_items,'[]'::jsonb)) = 0 then raise exception 'EMPTY_CART'; end if;

  -- Lock every product first and calculate totals.
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::numeric;
    v_unit_price := (v_item->>'unit_price_minor')::bigint;

    if v_qty <= 0 or v_unit_price < 0 then raise exception 'INVALID_ITEM'; end if;

    select * into v_product
    from public.products
    where id=(v_item->>'product_id')::uuid
      and organization_id=v_org
      and (branch_id=p_branch_id or branch_id is null)
      and active
    for update;

    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
    if v_product.stock_qty < v_qty then raise exception 'INSUFFICIENT_STOCK'; end if;

    v_line := round(v_qty * v_unit_price);
    v_subtotal := v_subtotal + v_line;
    v_cost := v_cost + round(v_qty * v_product.cost_minor);
  end loop;

  if p_discount_minor > v_subtotal then raise exception 'DISCOUNT_EXCEEDS_SUBTOTAL'; end if;
  v_total := v_subtotal - p_discount_minor;

  -- Payments must never exceed the sale total.
  for v_payment in select * from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb)) loop
    v_method := (v_payment->>'method')::public.payment_method;
    v_amount := (v_payment->>'amount_minor')::bigint;
    if v_amount <= 0 then raise exception 'INVALID_PAYMENT'; end if;
    v_paid := v_paid + v_amount;
  end loop;

  if v_paid > v_total then raise exception 'PAYMENT_EXCEEDS_TOTAL'; end if;
  v_due := v_total - v_paid;

  -- Daily sequence with row-level locking on a branch/day counter is ideal at scale.
  -- This starter uses a timestamp+random suffix to avoid race-condition duplicates.
  v_invoice := 'INV-' ||
    to_char(now() at time zone 'Asia/Qatar','YYYYMMDD-HH24MISS') ||
    '-' || upper(substr(replace(v_sale::text,'-',''),1,6));

  insert into public.sales(
    id,organization_id,branch_id,invoice_no,customer_id,cashier_user_id,
    subtotal_minor,discount_minor,tax_minor,total_minor,cost_minor,paid_minor,due_minor
  ) values(
    v_sale,v_org,p_branch_id,v_invoice,p_customer_id,v_uid,
    v_subtotal,p_discount_minor,0,v_total,v_cost,v_paid,v_due
  );

  -- Write line items + stock movement atomically.
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::numeric;
    v_unit_price := (v_item->>'unit_price_minor')::bigint;

    select * into v_product
    from public.products
    where id=(v_item->>'product_id')::uuid
    for update;

    v_line := round(v_qty * v_unit_price);

    insert into public.sale_items(
      sale_id,product_id,quantity,unit_price_minor,unit_cost_minor,line_total_minor
    ) values(
      v_sale,v_product.id,v_qty,v_unit_price,v_product.cost_minor,v_line
    );

    update public.products
    set stock_qty=stock_qty-v_qty,updated_at=now()
    where id=v_product.id;

    insert into public.inventory_movements(
      organization_id,branch_id,product_id,movement_type,quantity_delta,
      unit_cost_minor,reference_type,reference_id,created_by
    ) values(
      v_org,p_branch_id,v_product.id,'sale',-v_qty,v_product.cost_minor,
      'sale',v_sale,v_uid
    );
  end loop;

  for v_payment in select * from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb)) loop
    insert into public.sale_payments(sale_id,method,amount_minor)
    values(
      v_sale,
      (v_payment->>'method')::public.payment_method,
      (v_payment->>'amount_minor')::bigint
    );
  end loop;

  if p_customer_id is not null then
    if not exists(select 1 from public.customers where id=p_customer_id and organization_id=v_org and active)
      then raise exception 'CUSTOMER_ACCESS_DENIED'; end if;

    if v_due > 0 then
      update public.customers set balance_minor=balance_minor+v_due where id=p_customer_id;

      insert into public.customer_ledger(
        organization_id,customer_id,direction,amount_minor,reference_type,reference_id,created_by
      ) values(v_org,p_customer_id,'debit',v_due,'sale',v_sale,v_uid);
    end if;
  end if;

  insert into public.audit_logs(
    organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata
  ) values(
    v_org,p_branch_id,v_uid,'sale.created','sale',v_sale,
    jsonb_build_object('invoice_no',v_invoice,'total_minor',v_total)
  );

  return jsonb_build_object(
    'sale_id',v_sale,'invoice_no',v_invoice,'subtotal_minor',v_subtotal,
    'discount_minor',p_discount_minor,'total_minor',v_total,
    'paid_minor',v_paid,'due_minor',v_due,'cost_minor',v_cost
  );
end;
$$;

revoke all on function public.checkout_sale(uuid,uuid,bigint,jsonb,jsonb) from public, anon;
grant execute on function public.checkout_sale(uuid,uuid,bigint,jsonb,jsonb) to authenticated;
