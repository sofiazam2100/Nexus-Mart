# NexusMart V4.3 Migration Order

Run these migrations in order against the same Supabase project:

1. `0001_nexusmart_v4_core.sql` — organizations, branches, users/memberships, products, sales, purchases, customers, suppliers, inventory, returns, cash and audit tables.
2. `0002_nexusmart_v4_security.sql` — RLS, grants and organization-scoped read policies.
3. `0003_nexusmart_v4_transactions.sql` — organization onboarding and secure checkout foundation.
4. `0004_nexusmart_v4_reports.sql` — security-invoker daily sales reporting view.
5. `0005_nexusmart_v4_operations.sql` — inventory, customers, suppliers, purchases, expenses, cash register and return operations.
6. `0006_nexusmart_v4_control.sql` — V4.3 owner control layer: invoice sequencing, receipt/settings, role management, cash reconciliation hooks, customer/supplier payment cash movements, refund cash movements and negative-stock policy.

## Production verification

After migration, verify:
- RLS is enabled on every exposed table.
- `anon` has no table/function access unless deliberately required.
- `authenticated` has only the intended SELECT/table grants and explicitly granted RPC execution.
- Security-definer functions have a pinned `search_path` and explicit schema qualification.
- `supabase test db` passes the RLS test suite.
- A cashier cannot call manager/owner-only operations.
- A return cannot exceed remaining returnable quantity.
- Invoice numbers remain unique under concurrent checkout.
- Cash register expected-vs-actual variance is recorded at close.

7. `0007_nexusmart_v4_release.sql` — audit indexes, team invitation queue and owner invite controls.


### V4.5
- 0008_nexusmart_v4_expansion.sql — branches, batch/expiry, expense attachments, Storage policies, team invite acceptance, export-ready view.
- Deploy `supabase/functions/send-team-invite` with a server-only `SUPABASE_SECRET_KEY` before enabling email invitations.
