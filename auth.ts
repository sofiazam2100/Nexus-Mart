import { supabase } from './supabase'

export async function signIn(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password })
  if (error) throw error
  return data
}

export async function signUp(email: string, password: string) {
  const { data, error } = await supabase.auth.signUp({ email, password })
  if (error) throw error
  return data
}

export async function signOut() {
  const { error } = await supabase.auth.signOut()
  if (error) throw error
}

export async function getMyMemberships() {
  const { data, error } = await supabase
    .from('memberships')
    .select('id,organization_id,role,active,organizations(id,name_en,name_ar,name_bn),branch_memberships(branch_id,branches(id,name,code,active))')
    .eq('active', true)
  if (error) throw error
  return data ?? []
}

export async function createOrganization(input: {
  name_en: string
  name_ar?: string
  name_bn?: string
  cr_number?: string
  phone?: string
  whatsapp?: string
  branch_name?: string
  branch_code?: string
}) {
  const { data, error } = await supabase.rpc('create_organization', {
    p_name_en: input.name_en,
    p_name_ar: input.name_ar ?? '',
    p_name_bn: input.name_bn ?? '',
    p_cr_number: input.cr_number ?? null,
    p_phone: input.phone ?? null,
    p_whatsapp: input.whatsapp ?? null,
    p_branch_name: input.branch_name ?? 'Main Branch',
    p_branch_code: input.branch_code ?? 'MAIN',
  })
  if (error) throw error
  return data
}
