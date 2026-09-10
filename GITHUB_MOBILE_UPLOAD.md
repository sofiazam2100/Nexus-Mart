# NexusMart — GitHub Mobile Upload Edition

This edition intentionally keeps the Vite/React frontend source files at the repository root so GitHub's mobile file picker does not need to preserve folders.

## Required Vercel frontend files at repository root
- index.html
- package.json
- tsconfig.json
- vite.config.ts
- main.tsx
- App.tsx
- AuthScreen.tsx
- Onboarding.tsx
- ErrorBoundary.tsx
- auth.ts
- checkout.ts
- config.ts
- database.ts
- i18n.ts
- money.ts
- offlineQueue.ts
- supabase.ts
- styles.css
- manifest.json
- sw.js
- icon-192.svg
- icon-512.svg

`tsconfig.json` deliberately includes only the frontend source files. This prevents a root-level Supabase Edge Function `index.ts` (if retained in the GitHub repository) from being compiled by Vercel's frontend TypeScript build.

The Vite config copies the root PWA files into `dist` during build, so a `public/` folder is not required for the frontend deployment.

## Vercel environment variables
- VITE_SUPABASE_URL
- VITE_SUPABASE_PUBLISHABLE_KEY

Never put a Supabase secret/service-role key in Vercel frontend environment variables.
