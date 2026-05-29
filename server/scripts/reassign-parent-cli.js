#!/usr/bin/env node
"use strict";

/**
 * Emergency: set OnePlus (or any model) as parent for a user.
 *
 * Usage:
 *   node server/scripts/reassign-parent-cli.js --user-id 5 --model MT2111
 *   node server/scripts/reassign-parent-cli.js --phone 01712345678 --model MT2111
 *
 * Requires server/.env DB_* variables.
 */

require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });
const mysql = require("mysql2/promise");

function arg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? String(process.argv[i + 1] || "").trim() : "";
}

async function main() {
  const userId = arg("--user-id");
  const phone = arg("--phone");
  const model = arg("--model") || "MT2111";
  const hw = arg("--hardware-id");

  if (!userId && !phone) {
    console.error("Provide --user-id N or --phone 01XXXXXXXXX");
    process.exit(1);
  }

  const pool = mysql.createPool({
    host: process.env.DB_HOST || "127.0.0.1",
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER || "root",
    password: process.env.DB_PASSWORD || "",
    database: process.env.DB_NAME || "payment_checker",
  });

  try {
    let uid = userId;
    if (!uid) {
      const [u] = await pool.query("SELECT id FROM users WHERE phone = ? LIMIT 1", [phone]);
      if (!u.length) {
        console.error("User not found for phone:", phone);
        process.exit(1);
      }
      uid = u[0].id;
    }

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      let target;
      if (hw) {
        const [rows] = await conn.query(
          "SELECT id, device_model, device_id, is_parent, status FROM devices WHERE user_id = ? AND device_id = ? LIMIT 1",
          [uid, hw]
        );
        target = rows[0];
      } else {
        const [rows] = await conn.query(
          "SELECT id, device_model, device_id, is_parent, status FROM devices WHERE user_id = ? AND device_model LIKE ? LIMIT 1",
          [uid, `%${model}%`]
        );
        target = rows[0];
      }

      if (!target) {
        await conn.rollback();
        console.error("No device matched. List devices:");
        const [all] = await conn.query(
          "SELECT id, device_model, device_id, is_parent, status FROM devices WHERE user_id = ?",
          [uid]
        );
        console.table(all);
        process.exit(1);
      }

      await conn.query("UPDATE devices SET is_parent = 0 WHERE user_id = ?", [uid]);
      await conn.query("UPDATE devices SET is_parent = 1 WHERE user_id = ? AND id = ?", [uid, target.id]);
      await conn.commit();

      console.log("Parent reassigned OK:");
      console.log({
        userId: uid,
        deviceId: target.id,
        device_model: target.device_model,
        hardware: target.device_id,
      });
    } catch (e) {
      try {
        await conn.rollback();
      } catch (_) {}
      throw e;
    } finally {
      conn.release();
    }
  } finally {
    await pool.end();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
