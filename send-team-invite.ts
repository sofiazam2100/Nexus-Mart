import { createClient } from 'npm:@supabase/supabase-js@2'

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 })
  const authHeader = req.headers.get('Authorization') ?? ''
  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_PUBLISHABLE_KEY')!, { global: { headers: { Authorization: authHeader } } })
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return Response.json({ error: 'AUTH_REQUIRED' }, { status: 401 })
  const body = await req.json().catch(() => ({}))
  const email = String(body.email ?? '').trim().toLowerCase()
  const role = String(body.role ?? 'cashier')
  if (!email || !email.includes('@')) return Response.json({ error: 'INVALID_EMAIL' }, { status: 400 })

  const { data: membership } = await supabase.from('memberships').select('organization_id,role').eq('user_id', user.id).eq('active', true).eq('role', 'owner').maybeSingle()
  if (!membership) return Response.json({ error: 'OWNER_REQUIRED' }, { status: 403 })

  const secret = Deno.env.get('SUPABASE_SECRET_KEY')
  if (!secret) return Response.json({ error: 'SUPABASE_SECRET_KEY_NOT_CONFIGURED' }, { status: 500 })
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, secret)
  const { data: invite, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email)
  if (inviteError) return Response.json({ error: inviteError.message }, { status: 400 })
  const { data: row, error: dbError } = await admin.from('team_invites').insert({ organization_id: membership.organization_id, email, role, invited_by: user.id }).select('*').single()
  if (dbError) return Response.json({ error: dbError.message }, { status: 400 })
  return Response.json({ invite_id: row.id, user_id: invite.user?.id ?? null, status: row.status })
})
