# NexusMart V4.4 — Qatar Operations & Owner Control

NexusMart is a Qatar-first POS/business-control foundation aimed initially at small and medium retail businesses. The UI supports English, Arabic and Bangla data fields; customer-facing receipts are designed around Arabic + English by default.

## V4.4 highlights

- Secure Supabase Auth + organization/branch model
- RLS-protected multi-tenant data
- Server-side checkout, purchases, returns and payment mutations
- Branch-local sequential invoice numbers
- POS payment method selection
- Cash register open/close and variance
- Customer due collection
- Supplier payment
- Inventory CRUD and stock adjustment ledger
- Partial return validation
- Owner dashboard and daily sales/profit reports
- Receipt language and invoice-prefix settings
- Existing-member role management

## Run locally

```bash
cp .env.example .env
npm install
npm run dev
```

## Database

Apply migrations in `MIGRATION_ORDER.md` to a Supabase project. Use a publishable/anon client key in the frontend; never expose a Supabase service-role/secret key in browser code.

## Production status

This package is a production-oriented foundation, not a claim of completed Qatar legal/tax certification. Before selling it as a SaaS, connect it to a real Supabase project, run the migration and RLS test suite, configure backups, and perform end-to-end checkout/return/cash reconciliation tests.


## V4.4 release additions
- Professional browser-print receipt that can be saved as PDF, with Arabic + English labels.
- One-click WhatsApp-ready receipt/report sharing.
- Owner Audit Log screen for recent branch events.
- Date-range reporting for owner review.
- PWA manifest + lightweight offline shell fallback.
- Team invitation queue with owner-only create/revoke controls.
- Migration `0007_nexusmart_v4_release.sql`.

### Production note
The invitation queue records who should be invited; it does not itself send email. Connect it to a trusted server/Edge Function before production. Keep Supabase service/secret keys off the frontend.


## V4.5 expansion
- English / Bangla / Arabic shell language selector with RTL for Arabic.
- Owner branch creation and activation control.
- Product batch and expiry tracking.
- CSV exports for inventory and date-range reports.
- Private Supabase Storage bucket + expense document metadata.
- Team invite acceptance RPC and trusted `send-team-invite` Edge Function scaffold.

### Production secrets
Never put the Supabase secret key in the browser. Configure it only as an Edge Function secret. Supabase Edge Functions can validate the caller and use server-side secrets for privileged operations.
