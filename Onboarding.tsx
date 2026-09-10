import { FormEvent, useState } from 'react'
import { createOrganization } from '../lib/auth'

export default function Onboarding({ onDone }: { onDone: () => void }) {
  const [form,setForm]=useState({name_en:'',name_ar:'',name_bn:'',cr_number:'',phone:'',whatsapp:'',branch_name:'Main Branch',branch_code:'MAIN'})
  const [busy,setBusy]=useState(false); const [error,setError]=useState('')

  async function submit(e:FormEvent){
    e.preventDefault();setBusy(true);setError('')
    try { await createOrganization(form); onDone() }
    catch(e:any){setError(e.message??'Could not create business')}
    finally{setBusy(false)}
  }

  const update=(k:string,v:string)=>setForm(x=>({...x,[k]:v}))
  return <section className="onboarding panel">
    <div className="eyebrow">STEP 1 · BUSINESS SETUP</div>
    <h2>Set up your Qatar business</h2>
    <p>Enter the business details once. You can add branches and team members later.</p>
    <form className="form-grid" onSubmit={submit}>
      <label>Business name (English)<input required value={form.name_en} onChange={e=>update('name_en',e.target.value)}/></label>
      <label>اسم النشاط التجاري<input dir="rtl" value={form.name_ar} onChange={e=>update('name_ar',e.target.value)}/></label>
      <label>ব্যবসার নাম<input value={form.name_bn} onChange={e=>update('name_bn',e.target.value)}/></label>
      <label>CR number<input value={form.cr_number} onChange={e=>update('cr_number',e.target.value)}/></label>
      <label>Phone<input value={form.phone} onChange={e=>update('phone',e.target.value)}/></label>
      <label>WhatsApp<input value={form.whatsapp} onChange={e=>update('whatsapp',e.target.value)}/></label>
      <label>First branch<input required value={form.branch_name} onChange={e=>update('branch_name',e.target.value)}/></label>
      <label>Branch code<input required value={form.branch_code} onChange={e=>update('branch_code',e.target.value.toUpperCase())}/></label>
      {error && <div className="notice full">{error}</div>}
      <button className="primary full" disabled={busy}>{busy?'Creating…':'Create business'}</button>
    </form>
  </section>
}
