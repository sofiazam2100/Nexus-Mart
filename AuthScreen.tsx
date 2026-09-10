import { FormEvent, useState } from 'react'
import { signIn, signUp } from './auth'

export default function AuthScreen() {
  const [mode, setMode] = useState<'login'|'signup'>('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  async function submit(e: FormEvent) {
    e.preventDefault()
    setBusy(true); setError('')
    try {
      if (mode === 'login') await signIn(email, password)
      else await signUp(email, password)
    } catch (err: any) {
      setError(err.message ?? 'Authentication failed')
    } finally { setBusy(false) }
  }

  return <main className="auth-shell">
    <form className="auth-card" onSubmit={submit}>
      <div className="brand-mark">N</div>
      <h1>NexusMart <span>V4</span></h1>
      <p>Qatar-first POS & business control.</p>
      <label>Email<input type="email" required value={email} onChange={e=>setEmail(e.target.value)} /></label>
      <label>Password<input type="password" minLength={6} required value={password} onChange={e=>setPassword(e.target.value)} /></label>
      {error && <div className="notice">{error}</div>}
      <button disabled={busy}>{busy ? 'Please wait…' : mode === 'login' ? 'Sign in' : 'Create account'}</button>
      <small>বাংলা support · العربية receipts · English business controls</small>
      <button type="button" className="text-button" onClick={()=>setMode(mode==='login'?'signup':'login')}>
        {mode === 'login' ? 'Create a new owner account' : 'I already have an account'}
      </button>
    </form>
  </main>
}
