# B2B E2E Test Run Results

**Date:** automated agent run on dev machine  
**PostgreSQL:** not running (`ECONNREFUSED 127.0.0.1:5432`) — install/start PostgreSQL before full B2B tests.

## Completed automatically

| Step | Status | Notes |
|------|--------|-------|
| `.env` `USE_POSTGRES=1` + `PG_*` + `PUBLIC_API_BASE` | Done | [`server/.env`](../.env) |
| Node migration script | Added | `npm run pg:migrate` → `scripts/run-pg-migration.js` |
| Backend smoke script | Added | `npm run test:b2b` → `scripts/e2e-b2b-smoke.js` |
| API server restarted (port 3000) | Done | New routes loaded (`/checkout/:slug`, `/api/merchants`) |
| `GET /checkout/:slug` without Postgres | 503 | Server no longer crashes; Bengali maintenance message |
| `GET /health` | 200 | `{"ok":true}` |

## Blocked until PostgreSQL is up

| Step | Command after PG install |
|------|--------------------------|
| Apply SQL | `cd server && npm run pg:migrate` |
| Full backend smoke | `npm run test:b2b` |
| `is_used` + 409 Bengali | Included in smoke script |

## Manual (Flutter app on device)

1. Profile → **API Integration** → Add **Daraz Test**
2. Copy **API Secret** (shown once) and **Gateway URL** (real slug, e.g. `daraz-test-a1b2c3`)
3. **Checkout Designer** → map SIM to bKash block → Save
4. Browser: open Gateway URL
5. Submit real TrxID from ingested SMS (or use smoke script seed trx after PG works)

## Quick commands (when PostgreSQL runs)

```powershell
cd d:\payment_checker\server
npm run pg:migrate
npm run test:b2b
```

Expected smoke output: `Summary: N/N passed` including first verify 200, `is_used=true`, second verify 409 with Bengali message.

## Install PostgreSQL (Windows)

1. Download from https://www.postgresql.org/download/windows/
2. Create database: `CREATE DATABASE payment_checker;`
3. Set `PG_PASSWORD` in `server/.env`
4. Re-run `npm run pg:migrate` and `npm run test:b2b`
