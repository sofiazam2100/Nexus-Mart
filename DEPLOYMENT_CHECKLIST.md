# NexusMart V5 Commercial Launch Checklist

## 1. Supabase
- Create separate development and production projects.
- Set VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY only in the frontend environment.
- Never expose a service/secret key in Vite client code.
- Run all migrations in order, then run `supabase db advisors` and fix security/performance findings.
- Confirm every exposed table has appropriate RLS and grants.
- Deploy Edge Functions and keep JWT verification enabled for authenticated functions.
- Configure Storage policies for the private `expense-documents` bucket.

## 2. Auth
- Disable anonymous sign-in for commercial production.
- Configure email confirmation, password reset, rate limits and bot protection appropriate to the business.
- Test invitation acceptance with a real second user.

## 3. Financial integrity
- Test checkout, purchase, payment, return and cash-close transactions with concurrent users.
- Verify no negative stock unless the organization explicitly enables it.
- Verify invoice numbering is unique per branch.
- Verify refunds never exceed the original paid/credit-eligible amount.

## 4. Qatar configuration
- Configure Arabic + English receipt by default.
- Enter the merchant's actual legal/business details.
- Configure only the tax/excise profile that actually applies to the business.
- Do not market the product as tax/legal compliant solely because these fields exist; compliance depends on the merchant's setup and current requirements.

## 5. Production deployment
- Connect GitHub to the Supabase project or use CI/CD.
- Deploy the web frontend to a production host.
- Add a custom domain and HTTPS.
- Enable monitoring/error tracking.
- Back up/export data and document recovery procedures.
- Perform a staging smoke test before every production migration.

## 6. Launch acceptance
- Owner can create an organization and branch.
- Owner can invite a cashier.
- Cashier can sell but cannot change owner settings.
- Manager can manage permitted operational areas.
- Inventory changes create movements.
- Return cannot exceed remaining returnable quantity.
- Cash close shows expected vs actual variance.
- Reports reconcile to posted transactions.
