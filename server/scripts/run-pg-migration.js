"use strict";

/**
 * Run PostgreSQL migrations when psql CLI is not in PATH.
 * Usage: node scripts/run-pg-migration.js [001|002|all]
 */
require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });
const fs = require("fs");
const path = require("path");
const { Pool } = require("pg");

async function main() {
  const arg = process.argv[2] || "002";
  const files =
    arg === "all"
      ? ["001_payments_partitioned.sql", "002_merchants_b2b.sql"]
      : [`${arg === "002" ? "002_merchants_b2b" : "001_payments_partitioned"}.sql`];

  const pool = new Pool({
    host: process.env.PG_HOST || "127.0.0.1",
    port: Number(process.env.PG_PORT || 5432),
    user: process.env.PG_USER || "postgres",
    password: process.env.PG_PASSWORD || "",
    database: process.env.PG_DATABASE || "payment_checker",
  });

  try {
    await pool.query("SELECT 1");
    console.log("[pg-migrate] Connected to PostgreSQL");
  } catch (e) {
    console.error("[pg-migrate] Cannot connect:", e.message);
    console.error(
      "Install PostgreSQL or fix PG_* in server/.env, then re-run."
    );
    process.exit(1);
  }

  for (const file of files) {
    const fp = path.join(__dirname, "..", "migrations", "postgres", file);
    if (!fs.existsSync(fp)) {
      console.warn("[pg-migrate] skip missing", file);
      continue;
    }
    const sql = fs.readFileSync(fp, "utf8");
    console.log("[pg-migrate] applying", file);
    try {
      await pool.query(sql);
      console.log("[pg-migrate] ok", file);
    } catch (e) {
      if (e.message.includes("already exists")) {
        console.warn("[pg-migrate] partial (already exists):", file);
      } else {
        throw e;
      }
    }
  }

  const checks = await pool.query(`
    SELECT column_name FROM information_schema.columns
    WHERE table_name = 'payments' AND column_name = 'is_used'
  `);
  console.log(
    "[pg-migrate] payments.is_used:",
    checks.rows.length ? "yes" : "MISSING"
  );

  const m = await pool.query(
    `SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'merchants') AS ok`
  );
  console.log("[pg-migrate] merchants table:", m.rows[0].ok ? "yes" : "MISSING");

  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
