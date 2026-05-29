#!/usr/bin/env node
"use strict";

/**
 * Set a user's security PIN (proper pbkdf2 hash). Usage:
 *   node scripts/reset-account-pin.js --phone 01712345678 --pin 5566
 *   node scripts/reset-account-pin.js --user-id 5 --pin 5566
 */
require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });
const mysql = require("mysql2/promise");
const { hashPin, isValidPinFormat } = require("../utils/pinAuth");

async function main() {
  const args = process.argv.slice(2);
  let phone = "";
  let userId = null;
  let pin = "";
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--phone" && args[i + 1]) phone = args[++i];
    if (args[i] === "--user-id" && args[i + 1]) userId = Number(args[++i]);
    if (args[i] === "--pin" && args[i + 1]) pin = args[++i];
  }
  if (!isValidPinFormat(pin)) {
    console.error("PIN must be 4 to 6 digits");
    process.exit(1);
  }
  if (!phone && !userId) {
    console.error("Provide --phone or --user-id");
    process.exit(1);
  }

  const pool = mysql.createPool({
    host: process.env.DB_HOST || "127.0.0.1",
    user: process.env.DB_USER || "root",
    password: process.env.DB_PASSWORD || "",
    database: process.env.DB_NAME || "payment_checker",
  });

  try {
    let uid = userId;
    if (!uid) {
      const [rows] = await pool.query(
        "SELECT id FROM users WHERE phone = ? OR email = ? LIMIT 1",
        [phone, phone]
      );
      if (!rows.length) {
        console.error("User not found");
        process.exit(1);
      }
      uid = rows[0].id;
    }
    const stored = hashPin(pin);
    await pool.query("UPDATE users SET pin = ?, profile_complete = 1 WHERE id = ?", [
      stored,
      uid,
    ]);
    console.log(`OK: user id=${uid} PIN updated (pbkdf2 hash saved). Use PIN: ${pin} in the app.`);
  } finally {
    await pool.end();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
