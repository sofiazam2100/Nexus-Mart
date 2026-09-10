-- NexusMart V4.4 Qatar — audit viewer, invitation queue, reporting indexes
create table if not exists public.team_invites (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  email text not null,
  role public.app_role not null default 'cashier',
  branch_id uuid references public.branches(id) on delete set null,
  invited_by uuid not null references auth.users(id),
  status text not null default 'pending' check(status in ('pending','accepted','revoked','expired')),
  expires_at timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now()
);

create index if not exists team_invites_org_idx on public.team_invites(organization_id, created_at desc);
create index if not exists sales_branch_created_idx on public.sales(branch_id, created_at desc);
create index if not exists cash_movements_register_idx on public.cash_movements(register_id, created_at desc);
create index if not exists audit_branch_date_idx on public.audit_logs(branch_id, created_at desc);

alter table public.team_invites enable row level security;
revoke all on public.team_invites from anon;
grant select on public.team_invites to authenticated;

drop policy if exists team_invites_select on public.team_invites;
create policy team_invites_select on public.team_invites for select to authenticated
using (organization_id in (select public.my_org_ids()));

create or replace function public.create_team_invite(
  p_email text,
  p_role public.app_role,
  p_branch_id uuid default null
) returns public.team_invites
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_org uuid;
  v_row public.team_invites;
begin
  select organization_id into v_org from public.memberships
    where user_id=v_uid and active and role='owner' order by created_at limit 1;
  if v_org is null then raise exception 'OWNER_REQUIRED'; end if;
  if coalesce(trim(p_email),'')='' or position('@' in p_email)=0 then raise exception 'INVALID_EMAIL'; end if;
  if p_branch_id is not null and not exists(select 1 from public.branches where id=p_branch_id and organization_id=v_org and active) then
    raise exception 'BRANCH_NOT_FOUND';
  end if;
  insert into public.team_invites(organization_id,email,role,branch_id,invited_by)
  values(v_org,lower(trim(p_email)),p_role,p_branch_id,v_uid)
  returning * into v_row;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(v_org,v_uid,'member.invite_created','team_invite',v_row.id,jsonb_build_object('email',v_row.email,'role',v_row.role,'branch_id',v_row.branch_id));
  return v_row;
end; $$;
revoke all on function public.create_team_invite(text,public.app_role,uuid) from public,anon;
grant execute on function public.create_team_invite(text,public.app_role,uuid) to authenticated;

create or replace function public.revoke_team_invite(p_invite_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_org uuid;
begin
  select organization_id into v_org from public.team_invites where id=p_invite_id;
  if v_org is null then raise exception 'INVITE_NOT_FOUND'; end if;
  if not exists(select 1 from public.memberships where organization_id=v_org and user_id=v_uid and active and role='owner') then raise exception 'OWNER_REQUIRED'; end if;
  update public.team_invites set status='revoked' where id=p_invite_id and status='pending';
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(v_org,v_uid,'member.invite_revoked','team_invite',p_invite_id,'{}'::jsonb);
  return true;
end; $$;
revoke all on function public.revoke_team_invite(uuid) from public,anon;
grant execute on function public.revoke_team_invite(uuid) to authenticated;
