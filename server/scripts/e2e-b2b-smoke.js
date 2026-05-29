"use strict";

/**
 * Backend B2B smoke test (no Flutter required).
 * Prerequisites: USE_POSTGRES=1, migration 002 applied, server on PORT.
 *
 * Usage: node scripts/e2e-b2b-smoke.js
 */
require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });
const crypto = require("crypto");
const http = require("http");
const { Pool } = require("pg");

const PORT = Number(process.env.PORT || 3000);
const BASE = process.env.PUBLIC_API_BASE || `http://127.0.0.1:${PORT}`;
const TEST_TRX = "E2ETEST" + Date.now().toString().slice(-6);
const TEST_AMOUNT = 500;
const TEST_ACCOUNT_ID = Number(process.env.E2E_ACCOUNT_ID || 1);

function apiKeyPair() {
  const apiKeyId = `pk_live_${crypto.randomBytes(8).toString("hex")}`;
  const apiSecret = `sk_live_${crypto.randomBytes(16).toString("hex")}`;
  const hash = crypto.createHash("sha256").update(apiSecret).digest("hex");
  return { apiKeyId, apiSecret, hash };
}

function request(method, path, { headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE);
    const data = body ? JSON.stringify(body) : null;
    const req = http.request(
      url,
      {
        method,
        headers: {
          ...(data ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(data) } : {}),
          ...headers,
        },
      },
      (res) => {
        let raw = "";
        res.on("data", (c) => (raw += c));
        res.on("end", () => {
          let json = null;
          try {
            json = raw ? JSON.parse(raw) : null;
          } catch {
            json = { _raw: raw };
          }
          resolve({ status: res.statusCode, json, raw });
        });
      }
    );
    req.on("error", reject);
    if (data) req.write(data);
    req.end();
  });
}

async function main() {
  const results = [];
  const pass = (name) => {
    results.push({ name, ok: true });
    console.log("PASS:", name);
  };
  const fail = (name, detail) => {
    results.push({ name, ok: false, detail });
    console.error("FAIL:", name, detail);
  };

  if (process.env.USE_POSTGRES !== "1") {
    fail("USE_POSTGRES", "Set USE_POSTGRES=1 in server/.env");
    printSummary(results);
    process.exit(1);
  }

  const pool = new Pool({
    host: process.env.PG_HOST || "127.0.0.1",
    port: Number(process.env.PG_PORT || 5432),
    user: process.env.PG_USER || "postgres",
    password: process.env.PG_PASSWORD || "",
    database: process.env.PG_DATABASE || "payment_checker",
  });

  try {
    await pool.query("SELECT 1");
    pass("PostgreSQL connection");
  } catch (e) {
    fail("PostgreSQL connection", e.message);
    printSummary(results);
    process.exit(1);
  }

  const { apiKeyId, apiSecret, hash } = apiKeyPair();
  const slug = `daraz-test-${crypto.randomBytes(3).toString("hex")}`;

  const layout = {
    version: 1,
    blockOrder: ["bkash_personal"],
    blocks: {
      bkash_personal: {
        title: "বিকাশ পার্সোনাল — টেস্ট",
        numbers: [{ simSlot: 1, phone: "01712345678", enabled: true, position: 1 }],
      },
    },
  };

  let merchantId;
  try {
    const ins = await pool.query(
      `INSERT INTO merchants (account_id, site_name, domain_address, slug, api_key_id, api_secret_hash, checkout_layout)
       VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb)
       ON CONFLICT (account_id, slug) DO UPDATE SET is_active = TRUE
       RETURNING id`,
      [
        TEST_ACCOUNT_ID,
        "Daraz Test",
        "daraz.com",
        slug,
        apiKeyId,
        hash,
        JSON.stringify(layout),
      ]
    );
    merchantId = ins.rows[0]?.id;
    pass("Seed merchant Daraz Test");
  } catch (e) {
    fail("Seed merchant", e.message);
  }

  try {
    await pool.query(
      `INSERT INTO payments (account_id, receiver_number, provider_tag, amount, trx_id,
        sender_number, sms_timestamp, sms_date, sms_time, full_sms, is_used)
       VALUES ($1,$2,$3,$4,$5,$6,NOW(),CURRENT_DATE,'12:00:00',$7,FALSE)
       ON CONFLICT DO NOTHING`,
      [
        TEST_ACCOUNT_ID,
        "01712345678",
        "bKash Personal",
        TEST_AMOUNT,
        TEST_TRX,
        "",
        `TrxID ${TEST_TRX} Tk ${TEST_AMOUNT}`,
      ]
    );
    pass(`Seed payment trx=${TEST_TRX}`);
  } catch (e) {
    fail("Seed payment", e.message);
  }

  try {
    const health = await request("GET", "/health");
    if (health.status === 200) pass("GET /health");
    else fail("GET /health", `status ${health.status}`);
  } catch (e) {
    fail("GET /health", e.message);
  }

  try {
    const checkout = await request("GET", `/checkout/${slug}`);
    if (checkout.status === 200 && checkout.raw.includes("বিকাশ")) {
      pass("GET /checkout/:slug HTML");
    } else {
      fail("GET /checkout/:slug", `status ${checkout.status}`);
    }
  } catch (e) {
    fail("GET /checkout/:slug", e.message);
  }

  try {
    const v1 = await request("POST", "/api/v1/merchant/verify-payment", {
      headers: { "X-Api-Key": apiKeyId, "X-Api-Secret": apiSecret },
      body: {
        trx_id: TEST_TRX,
        amount: TEST_AMOUNT,
        merchant_order_id: "E2E-ORD-1",
      },
    });
    if (v1.status === 200 && v1.json?.code === "PAYMENT_VERIFIED") {
      pass("First verify-payment 200");
    } else {
      fail("First verify-payment", JSON.stringify(v1.json));
    }
  } catch (e) {
    fail("First verify-payment", e.message);
  }

  const row = await pool.query(
    `SELECT is_used FROM payments WHERE account_id = $1 AND trx_id = $2 LIMIT 1`,
    [TEST_ACCOUNT_ID, TEST_TRX]
  );
  if (row.rows[0]?.is_used === true) pass("payments.is_used = true");
  else fail("payments.is_used", JSON.stringify(row.rows[0]));

  try {
    const v2 = await request("POST", "/api/v1/merchant/verify-payment", {
      headers: { "X-Api-Key": apiKeyId, "X-Api-Secret": apiSecret },
      body: {
        trx_id: TEST_TRX,
        amount: TEST_AMOUNT,
        merchant_order_id: "E2E-ORD-2",
      },
    });
    const msg = v2.json?.message || "";
    if (
      v2.status === 409 &&
      msg.includes("ইতিমধ্যেই") &&
      msg.includes("অ্যাড করা")
    ) {
      pass("Second verify-payment 409 Bengali");
    } else {
      fail("Second verify-payment 409", JSON.stringify(v2.json));
    }
  } catch (e) {
    fail("Second verify-payment", e.message);
  }

  console.log("\nCheckout URL:", `${BASE}/checkout/${slug}`);
  console.log("API Key:", apiKeyId);
  console.log("API Secret:", apiSecret);

  await pool.end();
  printSummary(results);
  process.exit(results.every((r) => r.ok) ? 0 : 1);
}

function printSummary(results) {
  const ok = results.filter((r) => r.ok).length;
  console.log(`\n=== Summary: ${ok}/${results.length} passed ===`);
  for (const r of results.filter((x) => !x.ok)) {
    console.log(" -", r.name, r.detail || "");
  }
}

main();
