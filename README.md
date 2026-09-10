# send-team-invite

Deploy this Edge Function only after configuring the following project secrets:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_SECRET_KEY` (server-only; never expose to the browser)

The function validates the caller through Supabase Auth, requires an owner membership, sends a Supabase Auth invitation, and records the invitation in `team_invites`.
