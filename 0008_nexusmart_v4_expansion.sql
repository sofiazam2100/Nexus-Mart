-- NexusMart V4.5 Qatar — branch control, product batches, attachments, exports

create table if not exists public.product_batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  batch_no text not null,
  expiry_date date,
  quantity numeric(14,3) not null default 0 check(quantity >= 0),
  unit_cost_minor bigint not null default 0 check(unit_cost_minor >= 0),
  created_at timestamptz not null default now(),
  unique(branch_id, product_id, batch_no)
);

create table if not exists public.expense_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  expense_id uuid not null references public.expenses(id) on delete cascade,
  storage_path text not null,
  file_name text not null,
  content_type text,
  size_bytes bigint,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists product_batches_branch_expiry_idx on public.product_batches(branch_id, expiry_date);
create index if not exists product_batches_product_idx on public.product_batches(product_id);
create index if not exists expense_attachments_expense_idx on public.expense_attachments(expense_id);

alter table public.product_batches enable row level security;
alter table public.expense_attachments enable row level security;

create policy product_batches_select on public.product_batches for select to authenticated
using (organization_id in (select public.my_org_ids()));

create policy expense_attachments_select on public.expense_attachments for select to authenticated
using (organization_id in (select public.my_org_ids()));

revoke all on public.product_batches, public.expense_attachments from anon;
grant select on public.product_batches, public.expense_attachments to authenticated;

create or replace function public.create_branch(
  p_name text, p_code text, p_address text default null, p_phone text default null
) returns public.branches
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_org uuid; v_row public.branches;
begin
  select organization_id into v_org from public.memberships where user_id=v_uid and active and role='owner' order by created_at limit 1;
  if v_org is null then raise exception 'OWNER_REQUIRED'; end if;
  if coalesce(trim(p_name),'')='' or coalesce(trim(p_code),'')='' then raise exception 'INVALID_BRANCH'; end if;
  insert into public.branches(organization_id,name,code,address,phone)
  values(v_org,trim(p_name),upper(trim(p_code)),nullif(trim(p_address),''),nullif(trim(p_phone),'')) returning * into v_row;
  insert into public.invoice_sequences(branch_id,next_number) values(v_row.id,1) on conflict do nothing;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(v_org,v_uid,'branch.created','branch',v_row.id,jsonb_build_object('code',v_row.code));
  return v_row;
exception when unique_violation then raise exception 'BRANCH_CODE_EXISTS';
end; $$;
revoke all on function public.create_branch(text,text,text,text) from public,anon;
grant execute on function public.create_branch(text,text,text,text) to authenticated;

create or replace function public.set_branch_active(p_branch_id uuid,p_active boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_org uuid;
begin
  select organization_id into v_org from public.branches where id=p_branch_id;
  if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;
  if not exists(select 1 from public.memberships where organization_id=v_org and user_id=v_uid and active and role='owner') then raise exception 'OWNER_REQUIRED'; end if;
  if not p_active and (select count(*) from public.branches where organization_id=v_org and active) <= 1 then raise exception 'LAST_ACTIVE_BRANCH'; end if;
  update public.branches set active=p_active where id=p_branch_id;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(v_org,v_uid,'branch.status_changed','branch',p_branch_id,jsonb_build_object('active',p_active));
  return true;
end; $$;
revoke all on function public.set_branch_active(uuid,boolean) from public,anon;
grant execute on function public.set_branch_active(uuid,boolean) to authenticated;

create or replace function public.upsert_product_batch(
  p_branch_id uuid,p_product_id uuid,p_batch_no text,p_expiry_date date,p_quantity numeric,p_unit_cost_minor bigint
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_org uuid; v_id uuid;
begin
  select organization_id into v_org from public.branches where id=p_branch_id and active;
  if v_org is null then raise exception 'BRANCH_NOT_FOUND'; end if;
  perform public._assert_branch_access(p_branch_id,v_org,'inventory');
  if not exists(select 1 from public.products where id=p_product_id and organization_id=v_org and (branch_id=p_branch_id or branch_id is null)) then raise exception 'PRODUCT_NOT_FOUND'; end if;
  if coalesce(trim(p_batch_no),'')='' or p_quantity<0 or p_unit_cost_minor<0 then raise exception 'INVALID_BATCH'; end if;
  insert into public.product_batches(organization_id,branch_id,product_id,batch_no,expiry_date,quantity,unit_cost_minor)
  values(v_org,p_branch_id,p_product_id,trim(p_batch_no),p_expiry_date,p_quantity,p_unit_cost_minor)
  on conflict(branch_id,product_id,batch_no) do update set expiry_date=excluded.expiry_date,quantity=excluded.quantity,unit_cost_minor=excluded.unit_cost_minor
  returning id into v_id;
  insert into public.audit_logs(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(v_org,p_branch_id,v_uid,'inventory.batch_updated','product_batch',v_id,jsonb_build_object('batch_no',p_batch_no,'quantity',p_quantity,'expiry_date',p_expiry_date));
  return v_id;
end; $$;
revoke all on function public.upsert_product_batch(uuid,uuid,text,date,numeric,bigint) from public,anon;
grant execute on function public.upsert_product_batch(uuid,uuid,text,date,numeric,bigint) to authenticated;

-- Export-friendly views: always scoped by caller's organization and branch through joins.
create or replace view public.branch_product_snapshot with (security_invoker=true) as
select p.id,p.organization_id,p.branch_id,p.sku,p.barcode,p.name_en,p.name_ar,p.name_bn,
       p.cost_minor,p.selling_minor,p.stock_qty,p.reorder_level,p.active,
       coalesce(sum(case when b.expiry_date is not null and b.expiry_date < current_date then b.quantity else 0 end),0) as expired_qty,
       coalesce(sum(case when b.expiry_date is not null and b.expiry_date <= current_date + 30 then b.quantity else 0 end),0) as expiring_30d_qty
from public.products p
left join public.product_batches b on b.product_id=p.id and b.branch_id=p.branch_id
group by p.id;

revoke all on public.branch_product_snapshot from anon;
grant select on public.branch_product_snapshot to authenticated;

-- Private bucket for expense documents. Actual bucket creation is best done in the Dashboard or storage migration tooling.
insert into storage.buckets (id,name,public) values ('expense-documents','expense-documents',false) on conflict (id) do nothing;

drop policy if exists expense_docs_select on storage.objects;
create policy expense_docs_select on storage.objects for select to authenticated
using (bucket_id='expense-documents' and (storage.foldername(name))[1] in (select id::text from public.my_org_ids()));

drop policy if exists expense_docs_insert on storage.objects;
create policy expense_docs_insert on storage.objects for insert to authenticated
with check (bucket_id='expense-documents' and (storage.foldername(name))[1] in (select id::text from public.my_org_ids()));

drop policy if exists expense_docs_delete on storage.objects;
create policy expense_docs_delete on storage.objects for delete to authenticated
using (bucket_id='expense-documents' and (storage.foldername(name))[1] in (select id::text from public.my_org_ids()));

create or replace function public.accept_team_invite()
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_email text; v_invite public.team_invites; v_membership uuid;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select lower(email) into v_email from auth.users where id=v_uid;
  if v_email is null then raise exception 'USER_NOT_FOUND'; end if;
  select * into v_invite from public.team_invites where lower(email)=v_email and status='pending' and expires_at>now() order by created_at desc limit 1 for update;
  if not found then return false; end if;
  insert into public.memberships(organization_id,user_id,role) values(v_invite.organization_id,v_uid,v_invite.role)
  on conflict(organization_id,user_id) do update set role=excluded.role,active=true returning id into v_membership;
  if v_invite.branch_id is not null then insert into public.branch_memberships(membership_id,branch_id) values(v_membership,v_invite.branch_id) on conflict do nothing;
  else insert into public.branch_memberships(membership_id,branch_id) select v_membership,b.id from public.branches b where b.organization_id=v_invite.organization_id and b.active;
  end if;
  update public.team_invites set status='accepted' where id=v_invite.id;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(v_invite.organization_id,v_uid,'member.invite_accepted','team_invite',v_invite.id,jsonb_build_object('email',v_email));
  return true;
end; $$;
revoke all on function public.accept_team_invite() from public,anon; grant execute on function public.accept_team_invite() to authenticated;
