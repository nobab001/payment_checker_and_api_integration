-- Multi-merchant B2B gateway (shared account_id ledger)
-- Run after 001: psql -U postgres -d payment_checker -f migrations/postgres/002_merchants_b2b.sql

-- Payments: cross-site redemption flags
ALTER TABLE payments ADD COLUMN IF NOT EXISTS is_used BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS used_at TIMESTAMPTZ;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS used_by_merchant_id INTEGER;

CREATE INDEX IF NOT EXISTS idx_payments_verify_lookup
  ON payments (account_id, trx_id, amount)
  WHERE is_used = FALSE;

CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_trx_open
  ON payments (account_id, trx_id)
  WHERE is_used = FALSE
    AND trx_id <> ''
    AND trx_id NOT LIKE 'GEN%';

-- Merchants: multiple sites per Payment Checker user (account_id)
CREATE TABLE IF NOT EXISTS merchants (
  id                SERIAL PRIMARY KEY,
  account_id        INTEGER NOT NULL,
  site_name         VARCHAR(128) NOT NULL,
  domain_address    VARCHAR(255) NOT NULL DEFAULT '',
  slug              VARCHAR(64)  NOT NULL,
  api_key_id        VARCHAR(32)  NOT NULL,
  api_secret_hash   VARCHAR(255) NOT NULL,
  gateway_username  VARCHAR(64),
  checkout_layout   JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  rate_limit_rpm    INTEGER NOT NULL DEFAULT 120,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (account_id, slug),
  UNIQUE (api_key_id)
);

CREATE INDEX IF NOT EXISTS idx_merchants_account ON merchants (account_id);
CREATE INDEX IF NOT EXISTS idx_merchants_slug ON merchants (slug) WHERE is_active;

-- Redemption audit + per-merchant order uniqueness
CREATE TABLE IF NOT EXISTS payment_redemptions (
  id                  BIGSERIAL PRIMARY KEY,
  payment_id          BIGINT NOT NULL,
  account_id          INTEGER NOT NULL,
  merchant_id         INTEGER NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  merchant_order_id   VARCHAR(128) NOT NULL DEFAULT '',
  trx_id              VARCHAR(64) NOT NULL,
  amount              NUMERIC(12,2) NOT NULL DEFAULT 0,
  idempotency_key     VARCHAR(64),
  redeemed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (merchant_id, trx_id),
  UNIQUE (merchant_id, merchant_order_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_redemptions_idempotency
  ON payment_redemptions (merchant_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_redemptions_account_trx
  ON payment_redemptions (account_id, trx_id);
