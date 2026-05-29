"use strict";

const { getPostgresPool } = require("../db/postgresPool");

/**
 * Time-based cascading search — stops at first hit (1d → 7d → 30d → all-time).
 * Compound index: (account_id, provider_tag, trx_id, sms_timestamp DESC)
 */
async function searchPaymentsCascading({
  accountId,
  trxId,
  query,
  receiverNumber,
  providerTag,
}) {
  const pool = getPostgresPool();
  if (!pool) {
    return { window: null, results: [] };
  }

  const windows = [
    { key: "1d", interval: "1 day" },
    { key: "7d", interval: "7 days" },
    { key: "30d", interval: "30 days" },
    { key: "all", interval: null },
  ];

  for (const w of windows) {
    const rows = await _searchWindow(pool, {
      accountId,
      trxId,
      query,
      receiverNumber,
      providerTag,
      interval: w.interval,
    });
    if (rows.length > 0) {
      return { window: w.key, results: rows };
    }
  }
  return { window: null, results: [] };
}

async function _searchWindow(
  pool,
  { accountId, trxId, query, receiverNumber, providerTag, interval }
) {
  const where = ["account_id = $1"];
  const params = [accountId];
  let n = 2;

  if (providerTag) {
    where.push(`provider_tag = $${n++}`);
    params.push(providerTag.slice(0, 128));
  }
  if (receiverNumber) {
    where.push(`receiver_number = $${n++}`);
    params.push(receiverNumber.slice(0, 32));
  }
  if (trxId) {
    where.push(`trx_id = $${n++}`);
    params.push(trxId.slice(0, 64));
  } else if (query) {
    const q = String(query).trim();
    const digits = q.replace(/\D/g, "");
    if (digits.length >= 4) {
      where.push(
        `(trx_id ILIKE $${n} OR sender_number LIKE $${n + 1} OR receiver_number LIKE $${n + 1} OR full_sms ILIKE $${n})`
      );
      params.push(`%${q}%`, `%${digits}%`);
      n += 2;
    } else {
      where.push(`(trx_id ILIKE $${n} OR full_sms ILIKE $${n})`);
      params.push(`%${q}%`);
      n += 1;
    }
  }

  if (interval) {
    where.push(`sms_timestamp >= NOW() - INTERVAL '${interval}'`);
  }

  const sql = `
    SELECT id, account_id, device_id, sim_slot, receiver_number, provider_tag,
           amount, trx_id, sender_number, sms_timestamp, sms_date, sms_time,
           full_sms, created_at
    FROM payments
    WHERE ${where.join(" AND ")}
    ORDER BY sms_timestamp DESC
    LIMIT 100
  `;

  const { rows } = await pool.query(sql, params);
  return rows;
}

async function insertPaymentPostgres(row) {
  const pool = getPostgresPool();
  if (!pool) return null;

  const sql = `
    INSERT INTO payments (
      account_id, device_id, sim_slot, receiver_number, provider_tag,
      amount, trx_id, sender_number, sms_timestamp, sms_date, sms_time, full_sms,
      is_used
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12, FALSE)
    ON CONFLICT (account_id, trx_id, sms_timestamp) DO NOTHING
    RETURNING id
  `;
  const { rows } = await pool.query(sql, [
    row.accountId,
    row.deviceId,
    row.simSlot,
    row.receiverNumber,
    row.providerTag,
    row.amount,
    row.trxId,
    row.senderNumber,
    row.smsTimestamp,
    row.smsDate,
    row.smsTime,
    row.fullSms,
  ]);
  return rows[0]?.id ?? null;
}

module.exports = { searchPaymentsCascading, insertPaymentPostgres };
