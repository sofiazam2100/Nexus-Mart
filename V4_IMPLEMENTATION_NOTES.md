# NexusMart V4.4 Implementation Notes

## What changed

V4.4 moves NexusMart closer to a sellable Qatar-first SaaS product for small and medium retail businesses.

### Owner control
- Daily sales/profit dashboard.
- Customer receivables and supplier payables visibility.
- Low-stock visibility.
- Cash register workflow.
- Reports based on a server-side daily sales view.

### POS
- Cash/card/bank-transfer payment selection.
- Discount is clamped in the UI and validated again in the database.
- Checkout uses a database transaction.
- Invoice numbers now come from a branch-local sequence instead of timestamp-only identifiers.
- Cash payments are mirrored into an open cash register.

### Returns/refunds
- Return quantity is checked against previously returned quantity.
- Stock is restored through an inventory movement.
- Cash refunds require an open register and create a cash-out movement.
- Customer-credit returns are posted to the customer ledger.

### Receivables/payables
- Customer due collection creates a customer-ledger entry and cash movement for cash payments.
- Supplier payments create supplier-ledger entries and cash-out movements for cash payments.

### Team / permissions
- Owner can change existing member roles.
- Existing roles: owner, manager, cashier, accountant, inventory.
- V4.4 intentionally does not implement browser-side user invitations; those should be handled by a trusted server/admin flow.

### Settings
- Receipt language: Arabic + English, with optional Bangla.
- Invoice prefix.
- Receipt footer.
- Default tax profile.
- Negative-stock policy.

## Qatar positioning

The product should default to Arabic + English customer-facing invoices/receipts. Qatar's Ministry of Commerce and Industry states that detailed invoices must be in Arabic in addition to another language. Do not claim “MOCI compliant” or “VAT invoice” merely because the UI has Arabic text; compliance depends on the merchant's actual registration, tax status and final invoice implementation.

## Known next-release items

- Trusted invitation flow for team members.
- Branch-local role scope UI.
- Dedicated payment/reconciliation report.
- Proper invoice/credit-note PDF renderer.
- Exact Qatar tax/excise configuration and product-level tax profiles.
- Audit-log viewer.
- WhatsApp/share integrations.
- PWA/offline queue.
- Automated backup/export and subscription/billing.


## V4.4 verification notes
- Frontend dependency installation could not be completed in this environment because `npm install` timed out; therefore a full Vite production build was not claimed.
- Static source and migration files were inspected after modification.
- The release keeps financial writes in database functions and keeps exposed data behind grants + RLS.
- Receipt printing uses the browser print dialog; users can select “Save as PDF”.
- PWA shell caching is intentionally lightweight and does not pretend that financial transactions work offline; financial mutations still require the live authenticated backend.
