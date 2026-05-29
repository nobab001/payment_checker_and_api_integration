"use strict";

const crypto = require("crypto");

/** @type {import("mysql2/promise").Pool | null} */
let mysqlPool = null;

function setMysqlPool(pool) {
  mysqlPool = pool;
}

function requirePool() {
  if (!mysqlPool) {
    const e = new Error("Database pool not initialized");
    e.statusCode = 503;
    throw e;
  }
  return mysqlPool;
}

const DEFAULT_LAYOUT = {
  version: 1,
  blockOrder: [
    "bkash_personal",
    "nagad_personal",
    "rocket_personal",
    "upay_personal",
    "bkash_agent",
    "nagad_agent",
    "bank_accounts",
  ],
  blocks: {},
};

function slugify(name, domain) {
  const base = (name || domain || "site")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 48);
  const suffix = crypto.randomBytes(3).toString("hex");
  return `${base || "merchant"}-${suffix}`;
}

function generateApiCredentials() {
  const apiKeyId = `pk_live_${crypto.randomBytes(12).toString("hex")}`;
  const apiSecret = `sk_live_${crypto.randomBytes(24).toString("hex")}`;
  const hash = crypto.createHash("sha256").update(apiSecret).digest("hex");
  return { apiKeyId, apiSecret, apiSecretHash: hash };
}

function maskApiKeyId(apiKeyId) {
  if (!apiKeyId || apiKeyId.length < 12) return "pk_live_****";
  return `${apiKeyId.slice(0, 12)}…${apiKeyId.slice(-4)}`;
}

function publicGatewayBase(req) {
  const env = process.env.PUBLIC_API_BASE || process.env.API_PUBLIC_URL;
  if (env) return String(env).replace(/\/$/, "");
  const proto = req.headers["x-forwarded-proto"] || req.protocol || "http";
  const host = req.headers["x-forwarded-host"] || req.get("host");
  return `${proto}://${host}`;
}

function parseLayout(row) {
  if (!row?.checkout_layout) return DEFAULT_LAYOUT;
  if (typeof row.checkout_layout === "object") return row.checkout_layout;
  try {
    return JSON.parse(row.checkout_layout);
  } catch {
    return DEFAULT_LAYOUT;
  }
}

async function listMerchants(accountId) {
  const pool = requirePool();
  const [rows] = await pool.query(
    `SELECT id, account_id, site_name, domain_address, slug, api_key_id,
            gateway_username, is_active, created_at, updated_at
     FROM merchants WHERE account_id = ? ORDER BY id DESC`,
    [accountId]
  );
  return rows;
}

async function getMerchantById(accountId, merchantId) {
  const pool = requirePool();
  const [rows] = await pool.query(
    `SELECT id, account_id, site_name, domain_address, slug, api_key_id,
            gateway_username, checkout_layout, is_active, created_at, updated_at
     FROM merchants WHERE id = ? AND account_id = ? LIMIT 1`,
    [merchantId, accountId]
  );
  const row = rows[0];
  if (row) row.checkout_layout = parseLayout(row);
  return row || null;
}

async function getMerchantBySlug(slug) {
  const pool = requirePool();
  const [rows] = await pool.query(
    `SELECT id, account_id, site_name, domain_address, slug, api_key_id,
            api_secret_hash, gateway_username, checkout_layout, is_active
     FROM merchants WHERE slug = ? AND is_active = 1 LIMIT 1`,
    [slug]
  );
  const row = rows[0];
  if (row) row.checkout_layout = parseLayout(row);
  return row || null;
}

async function getMerchantByApiKeyId(apiKeyId) {
  const pool = requirePool();
  const [rows] = await pool.query(
    `SELECT id, account_id, site_name, domain_address, slug, api_key_id,
            api_secret_hash, gateway_username, checkout_layout, is_active
     FROM merchants WHERE api_key_id = ? AND is_active = 1 LIMIT 1`,
    [apiKeyId]
  );
  const row = rows[0];
  if (row) row.checkout_layout = parseLayout(row);
  return row || null;
}

async function createMerchant(accountId, { siteName, domainAddress, gatewayUsername }) {
  const pool = requirePool();
  const { apiKeyId, apiSecret, apiSecretHash } = generateApiCredentials();
  const slug = slugify(siteName, domainAddress);

  const [result] = await pool.query(
    `INSERT INTO merchants
       (account_id, site_name, domain_address, slug, api_key_id, api_secret_hash,
        gateway_username, checkout_layout)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      accountId,
      String(siteName).slice(0, 128),
      String(domainAddress || "").slice(0, 255),
      slug,
      apiKeyId,
      apiSecretHash,
      gatewayUsername ? String(gatewayUsername).slice(0, 64) : null,
      JSON.stringify(DEFAULT_LAYOUT),
    ]
  );

  const [rows] = await pool.query(
    `SELECT id, account_id, site_name, domain_address, slug, api_key_id,
            gateway_username, is_active, created_at
     FROM merchants WHERE id = ?`,
    [result.insertId]
  );

  return { merchant: rows[0], apiSecret };
}

async function updateMerchant(accountId, merchantId, patch) {
  const pool = requirePool();
  const sets = [];
  const params = [];

  if (patch.isActive !== undefined) {
    sets.push("is_active = ?");
    params.push(patch.isActive ? 1 : 0);
  }
  if (patch.domainAddress !== undefined) {
    sets.push("domain_address = ?");
    params.push(String(patch.domainAddress).slice(0, 255));
  }
  if (patch.siteName !== undefined) {
    sets.push("site_name = ?");
    params.push(String(patch.siteName).slice(0, 128));
  }

  if (!sets.length) return getMerchantById(accountId, merchantId);

  params.push(merchantId, accountId);
  await pool.query(
    `UPDATE merchants SET ${sets.join(", ")}, updated_at = NOW()
     WHERE id = ? AND account_id = ?`,
    params
  );
  return getMerchantById(accountId, merchantId);
}

async function saveCheckoutLayout(accountId, merchantId, layout) {
  const pool = requirePool();
  const [result] = await pool.query(
    `UPDATE merchants SET checkout_layout = ?, updated_at = NOW()
     WHERE id = ? AND account_id = ?`,
    [JSON.stringify(layout), merchantId, accountId]
  );
  return result.affectedRows ? { id: merchantId } : null;
}

async function regenerateApiKey(accountId, merchantId) {
  const pool = requirePool();
  const { apiKeyId, apiSecret, apiSecretHash } = generateApiCredentials();
  const [result] = await pool.query(
    `UPDATE merchants SET api_key_id = ?, api_secret_hash = ?, updated_at = NOW()
     WHERE id = ? AND account_id = ?`,
    [apiKeyId, apiSecretHash, merchantId, accountId]
  );
  if (!result.affectedRows) return null;
  const [rows] = await pool.query(
    `SELECT id, api_key_id, slug FROM merchants WHERE id = ?`,
    [merchantId]
  );
  return { merchant: rows[0], apiSecret };
}

module.exports = {
  setMysqlPool,
  requirePool,
  DEFAULT_LAYOUT,
  slugify,
  maskApiKeyId,
  publicGatewayBase,
  listMerchants,
  getMerchantById,
  getMerchantBySlug,
  getMerchantByApiKeyId,
  createMerchant,
  updateMerchant,
  saveCheckoutLayout,
  regenerateApiKey,
};
