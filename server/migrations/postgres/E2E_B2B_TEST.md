# Multi-Merchant B2B — E2E test checklist

## Setup

1. Apply `001` + `002` SQL migrations.

```powershell
cd server
npm run pg:migrate
# or: psql -U postgres -d payment_checker -f migrations/postgres/002_merchants_b2b.sql
```

2. Set `USE_POSTGRES=1` in `server/.env`, restart API (`npm run dev`).

3. **Automated backend smoke (no Flutter):**

```powershell
npm run test:b2b
```

See latest run notes: [E2E_RUN_RESULTS.md](./E2E_RUN_RESULTS.md)
3. Login on Flutter app, configure Device Settings (SIM + senders), start monitoring.
4. Ingest a test payment SMS (or POST `/api/payment-sms-ingest`).

## Tests

| # | Step | Expected |
|---|------|----------|
| 1 | Profile → API Integration → Add site "Daraz" | 201, `api_secret` shown once |
| 2 | Add site "Alibaba" same account | 2 merchants, same `account_id` in DB |
| 3 | Regenerate API key without PIN | 403 |
| 4 | Regenerate with correct Security PIN | New `api_secret` once |
| 5 | `POST /api/v1/merchant/verify-payment` (Daraz keys) valid trx | 200 `PAYMENT_VERIFIED`, `is_used=true` |
| 6 | Same trx + amount on Alibaba keys | 409 Bengali already-redeemed message |
| 7 | Invalid trx | 404 |
| 8 | Open `GET /checkout/{slug}` | HTML blocks from saved layout |
| 9 | Submit TrxID on checkout form | Success/error flash in Bengali |
| 10 | Background SMS still arrives | Local SQLite + ingest unchanged |

## Verify-payment curl (merchant server)

```bash
curl -X POST http://localhost:3000/api/v1/merchant/verify-payment \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: pk_live_..." \
  -H "X-Api-Secret: sk_live_..." \
  -d '{"trx_id":"YOUR_TRX","amount":500,"merchant_order_id":"ORD-1"}'
```
