# PostgreSQL migration (payments)

## Prerequisites

- PostgreSQL 14+ installed
- Node dependency: `pg` (installed via `npm install` in `server/`)

## 1. Create database

```bash
psql -U postgres -c "CREATE DATABASE payment_checker;"
```

## 2. Apply schema (partitioning + compound index)

```bash
cd server
psql -U postgres -d payment_checker -f migrations/postgres/001_payments_partitioned.sql
psql -U postgres -d payment_checker -f migrations/postgres/002_merchants_b2b.sql
```

## 3. Configure `.env`

```env
USE_POSTGRES=1
PG_HOST=127.0.0.1
PG_PORT=5432
PG_USER=postgres
PG_PASSWORD=your_password
PG_DATABASE=payment_checker
```

MySQL/MariaDB can remain for `users`, `devices`, OTP until full cutover.

## 4. Install `pg` and restart API

```bash
cd server
npm install pg
npm run dev
```

## 5. Verify search API

```bash
curl -X POST http://localhost:3000/api/payments/search \
  -H "Authorization: Bearer YOUR_JWT" \
  -H "Content-Type: application/json" \
  -d '{"trx_id":"ABC123","query":"ABC"}'
```

Response includes `window`: `1d` | `7d` | `30d` | `all`.

## Partitioning note

`provider_tag` is indexed (not LIST-partitioned) because custom sender names are dynamic.
`account_id` HASH partitioning ensures each user's crores of rows stay in one of 8 shards.
