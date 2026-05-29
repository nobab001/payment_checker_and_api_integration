-- PostgreSQL payments store — partitioned by account_id (HASH)
-- Run: psql -U postgres -d payment_checker -f server/migrations/postgres/001_payments_partitioned.sql

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Parent table: HASH partition on account_id keeps each user's data in a shard
CREATE TABLE IF NOT EXISTS payments (
  id              BIGSERIAL,
  account_id      INTEGER NOT NULL,
  device_id       VARCHAR(255),
  sim_slot        SMALLINT,
  receiver_number VARCHAR(32),
  provider_tag    VARCHAR(128) NOT NULL DEFAULT '',
  amount          NUMERIC(12,2) NOT NULL DEFAULT 0,
  trx_id          VARCHAR(64) NOT NULL DEFAULT '',
  sender_number   VARCHAR(32),
  sms_timestamp   TIMESTAMPTZ NOT NULL,
  sms_date        DATE,
  sms_time        VARCHAR(16),
  full_sms        TEXT NOT NULL DEFAULT '',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (account_id, id),
  UNIQUE (account_id, trx_id, sms_timestamp)
) PARTITION BY HASH (account_id);

-- 8 shards (scale to 16/32 on production)
CREATE TABLE IF NOT EXISTS payments_p0 PARTITION OF payments FOR VALUES WITH (MODULUS 8, REMAINDER 0);
CREATE TABLE IF NOT EXISTS payments_p1 PARTITION OF payments FOR VALUES WITH (MODULUS 8, REMAINDER 1);
CREATE TABLE IF NOT EXISTS payments_p2 PARTITION OF payments FOR VALUES WITH (MODULUS 8, REMAINDER 2);
CREATE TABLE IF NOT EXISTS payments_p3 PARTITION OF payments FOR VALUES WITH (MODULUS 8, REMAINDER 3);
CREATE TABLE IF NOT EXISTS payments_p4 PARTITION OF payments FOR VALUES WITH (MODULUS 8, REMAINDER 4);
CREATE TABLE IF NOT EXISTS payments_p5 PARTITION OF payments FOR VALUES WITH (MODULUS 8, REMAINDER 5);
CREATE TABLE IF NOT EXISTS payments_p6 PARTITION OF payments FOR VALUES WITH (MODULUS 8, REMAINDER 6);
CREATE TABLE IF NOT EXISTS payments_p7 PARTITION OF payments FOR VALUES WITH (MODULUS 8, REMAINDER 7);

-- B-tree compound index for millisecond lookups within an account shard
CREATE INDEX IF NOT EXISTS idx_payments_compound
  ON payments (account_id, provider_tag, trx_id, sms_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_payments_receiver
  ON payments (account_id, receiver_number);

CREATE INDEX IF NOT EXISTS idx_payments_sender_digits
  ON payments (account_id, sender_number);

-- Optional: BRIN on time for very large all-time scans (Step 4 fallback)
CREATE INDEX IF NOT EXISTS idx_payments_sms_ts_brin
  ON payments USING BRIN (sms_timestamp);

COMMENT ON TABLE payments IS
  'Partitioned payment SMS — account_id=users.id; provider_tag=bKash/Nagad/etc.';
