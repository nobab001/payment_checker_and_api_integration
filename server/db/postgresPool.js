"use strict";

const { Pool } = require("pg");

let pool = null;

/**
 * PostgreSQL pool — enabled when USE_POSTGRES=1 in .env
 * Payments search + ingest use this; auth/devices may stay on MySQL during migration.
 */
function getPostgresPool() {
  if (process.env.USE_POSTGRES !== "1") return null;
  if (!pool) {
    pool = new Pool({
      host: process.env.PG_HOST || "127.0.0.1",
      port: Number(process.env.PG_PORT || 5432),
      user: process.env.PG_USER || "postgres",
      password: process.env.PG_PASSWORD || "",
      database: process.env.PG_DATABASE || "payment_checker",
      max: Number(process.env.PG_POOL_MAX || 20),
      idleTimeoutMillis: 30000,
    });
    pool.on("error", (err) => {
      console.error("[postgres] pool error:", err.message);
    });
  }
  return pool;
}

async function pgQuery(text, params) {
  const p = getPostgresPool();
  if (!p) return null;
  return p.query(text, params);
}

module.exports = { getPostgresPool, pgQuery };
