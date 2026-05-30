"use strict";

/**
 * Payment Checker API — Express + MariaDB/MySQL
 * Mirrors VPS deployment: BD mobile → SMS via `sms_settings` (e.g. BulkSMSBD template);
 * @gmail.com → OTP email via Nodemailer (GMAIL_USER + GMAIL_APP_PASSWORD). Both use `otps`.
 *
 * JSON keys aligned with Flutter: success, token, user (camelCase user fields),
 * exists, message, isNewUser on verify.
 */

require("dotenv").config();
const path = require("path");
const http = require("http");
const express = require("express");
const cors = require("cors");
const { Server } = require("socket.io");
const mysql = require("mysql2/promise");
const jwt = require("jsonwebtoken");
const nodemailer = require("nodemailer");

const PORT = Number(process.env.PORT || 3000);
/** Set when Socket.io starts — used by verify-otp for parent push notifications. */
let deviceIo = null;
const JWT_SECRET = process.env.JWT_SECRET || "change-me-in-production";
const JWT_EXPIRES = process.env.JWT_EXPIRES || "30d";
const OTP_EXPIRY_MIN = Number(process.env.OTP_EXPIRY_MIN || 10);
const RESEND_COOLDOWN_SEC = Number(process.env.OTP_RESEND_COOLDOWN_SEC || 60);

/** Gmail account that sends OTP mail (App Password in GMAIL_APP_PASSWORD). */
const GMAIL_USER = process.env.GMAIL_USER || "";
// Support both GMAIL_APP_PASSWORD and GMAIL_PASS env variable names
const GMAIL_APP_PASSWORD = String(
  process.env.GMAIL_APP_PASSWORD || process.env.GMAIL_PASS || ""
).replace(/\s+/g, "");

let _gmailTransport = null;
function getGmailTransport() {
  if (!GMAIL_USER || !GMAIL_APP_PASSWORD) return null;
  if (!_gmailTransport) {
    _gmailTransport = nodemailer.createTransport({
      service: "gmail",
      auth: { user: GMAIL_USER, pass: GMAIL_APP_PASSWORD },
    });
  }
  return _gmailTransport;
}

async function sendViaTransport(transport, toAddress, code, fromEmail) {
  const from = process.env.GMAIL_FROM || fromEmail;
  const subject = process.env.GMAIL_OTP_SUBJECT || "আপনার OTP কোড - Payment Checker";
  await transport.sendMail({
    from: `"Payment Checker" <${from}>`,
    to: toAddress,
    subject,
    text: `আপনার Payment Checker OTP: ${code}। কাউকে বলবেন না।`,
    html: `
      <div style="font-family:sans-serif;max-width:480px;margin:auto;padding:24px;border:1px solid #e0e0e0;border-radius:12px">
        <h2 style="color:#1A237E;margin:0 0 12px">Payment Checker</h2>
        <p style="font-size:16px">আপনার OTP কোড:</p>
        <p style="font-size:28px;font-weight:bold;letter-spacing:4px;color:#1A237E">${code}</p>
        <p style="color:#666;font-size:14px">এই কোড কাউকে দেবেন না।</p>
      </div>`,
  });
}

/**
 * Send 6-digit OTP to the user's Gmail using round-robin from email_accounts.
 * Falls back to env-based single account if no DB accounts configured.
 */
async function sendOtpToGmail(toAddress, code) {
  // 1. Try database email_accounts first (round-robin)
  try {
    const [accounts] = await pool.query(
      "SELECT * FROM email_accounts WHERE is_active = 1 ORDER BY id ASC"
    );

    if (accounts.length > 0) {
      // Find first account that hasn't hit its daily limit
      let account = accounts.find((a) => a.sent_count < a.daily_limit);

      // If all accounts at limit, reset all counters and use first
      if (!account) {
        await pool.query("UPDATE email_accounts SET sent_count = 0 WHERE is_active = 1");
        account = accounts[0];
      }

      const transport = nodemailer.createTransport({
        service: "gmail",
        auth: { user: account.email, pass: account.app_password },
      });

      await sendViaTransport(transport, toAddress, code, account.email);

      // Increment counter for this account
      await pool.query(
        "UPDATE email_accounts SET sent_count = sent_count + 1 WHERE id = ?",
        [account.id]
      );
      return;
    }
  } catch (dbErr) {
    console.error("[sendOtpToGmail] DB round-robin failed, falling back to env:", dbErr.message);
  }

  // 2. Fallback to env-based single Gmail account
  const transport = getGmailTransport();
  if (!transport) {
    const err = new Error(
      "Gmail OTP not configured: add email accounts in admin or set GMAIL_USER and GMAIL_APP_PASSWORD in .env"
    );
    err.statusCode = 503;
    throw err;
  }
  await sendViaTransport(transport, toAddress, code, GMAIL_USER);
}

const pool = mysql.createPool({
  host: process.env.DB_HOST || "127.0.0.1", // 127.0.0.1 avoids DNS lookup unlike 'localhost'
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || "root",
  password: process.env.DB_PASSWORD || "",
  database: process.env.DB_NAME || "payment_checker",
  waitForConnections: true,
  connectionLimit: 10,
  connectTimeout: 8000,
});

const { registerDeviceRoutes } = require("./controllers/deviceController");
const { registerPaymentPostgresRoutes } = require("./routes/paymentPostgresRoutes");
const { registerMerchantRoutes } = require("./routes/merchantRoutes");
const { registerCheckoutPublicRoutes } = require("./routes/checkoutPublicRoutes");
const { insertPaymentPostgres } = require("./services/paymentSearchService");
const { registerAuthDeviceRoutes } = require("./controllers/auth_controller");
const { registerPinRoutes } = require("./controllers/pinController");
const { registerDeviceSocket } = require("./socket/deviceSocket");
const { registerOrUpdateDevice } = require("./services/deviceRegistration");
const { initAuthCredentialTables } = require("./services/authSchemaInit");
const {
  isBdPhone,
  isGmail,
  normalizeContact,
  isUserBlocked,
  findUserByCredential,
  ensureCredential,
  evaluateDeviceBinding,
  evaluateDeviceLoginEligibility,
  bindDeviceToUser,
  createUserWithPrimaryCredential,
} = require("./services/credentialAuth");
const { deviceNeedsSecurityPin } = require("./utils/deviceAuthPolicy");
const {
  hashPin,
  verifyUserPin,
  upgradePinHashIfNeeded,
  isValidPinFormat,
  isPinHashStorageValid,
} = require("./utils/pinAuth");

async function addDevicesColumnIfMissing(sql, label) {
  try {
    await pool.query(sql);
  } catch (e) {
    if (e.code !== "ER_DUP_FIELDNAME") {
      console.warn(`[initDevicesTable] ${label}:`, e.message || e);
    }
  }
}

async function initSettingsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS settings (
      setting_key VARCHAR(64) PRIMARY KEY,
      setting_value TEXT NOT NULL,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
  
  const defaults = {
    global: JSON.stringify({ smsApiEnabled: true, gmailApiEnabled: true, userRegistrationEnabled: true, appEnabled: true }),
    socialLinks: JSON.stringify({ whatsapp: "", facebook: "", telegram: "", youtube: "" }),
    paymentSettings: JSON.stringify({ bkashApiKey: "", bkashSecretKey: "", bkashAppId: "", bkashPassword: "", testMode: true, bkashCallbackUrl: "" })
  };

  for (const [key, val] of Object.entries(defaults)) {
    await pool.query(
      `INSERT INTO settings (setting_key, setting_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE setting_key = setting_key`,
      [key, val]
    );
  }
}

/** \`devices\` table + \`custom_name\`, \`status\`, \`is_parent\`. */
async function initDevicesTable() {
  let needsParentBackfill = false;
  await pool.query(`
    CREATE TABLE IF NOT EXISTS devices (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      device_id VARCHAR(255) NOT NULL,
      device_name VARCHAR(255) NOT NULL DEFAULT 'My Phone',
      custom_name VARCHAR(255) DEFAULT NULL,
      status ENUM('pending','active') NOT NULL DEFAULT 'pending',
      is_parent TINYINT(1) NOT NULL DEFAULT 0,
      device_model VARCHAR(255) NOT NULL DEFAULT '',
      android_version VARCHAR(64) NOT NULL DEFAULT '',
      sim1_number VARCHAR(32) DEFAULT NULL,
      sim1_operator VARCHAR(64) DEFAULT NULL,
      sim2_number VARCHAR(32) DEFAULT NULL,
      sim2_operator VARCHAR(64) DEFAULT NULL,
      sms_filter_enabled TINYINT(1) NOT NULL DEFAULT 1,
      block_unknown TINYINT(1) NOT NULL DEFAULT 0,
      block_incoming TINYINT(1) NOT NULL DEFAULT 0,
      allowed_keywords TEXT,
      blocked_keywords TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      last_seen_at TIMESTAMP NULL DEFAULT NULL,
      last_battery_percent TINYINT UNSIGNED NULL DEFAULT NULL,
      UNIQUE KEY uniq_user_device (user_id, device_id),
      INDEX idx_devices_user (user_id),
      CONSTRAINT fk_devices_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
  try {
    await pool.query(
      `ALTER TABLE devices ADD COLUMN custom_name VARCHAR(255) DEFAULT NULL AFTER device_name`
    );
  } catch (e) {
    if (e.code !== "ER_DUP_FIELDNAME") throw e;
  }
  try {
    await pool.query(
      `ALTER TABLE devices ADD COLUMN status ENUM('pending','active') NOT NULL DEFAULT 'active' AFTER custom_name`
    );
    needsParentBackfill = true;
  } catch (e) {
    if (e.code !== "ER_DUP_FIELDNAME") throw e;
  }
  try {
    await pool.query(
      `ALTER TABLE devices ADD COLUMN is_parent TINYINT(1) NOT NULL DEFAULT 0 AFTER status`
    );
    needsParentBackfill = true;
  } catch (e) {
    if (e.code !== "ER_DUP_FIELDNAME") throw e;
  }
  if (needsParentBackfill) {
    await pool.query(`UPDATE devices SET status = 'active' WHERE status IS NULL OR status = ''`);
    await pool.query(`UPDATE devices SET is_parent = 0`);
    await pool.query(`
      UPDATE devices d
      INNER JOIN (
        SELECT user_id, MIN(id) AS mid FROM devices GROUP BY user_id
      ) t ON d.user_id = t.user_id AND d.id = t.mid
      SET d.is_parent = 1
    `);
  }
  // Add presence/battery columns without AFTER — avoids ER_BAD_FIELD_ERROR if column order differs.
  try {
    await pool.query(
      `ALTER TABLE devices ADD COLUMN last_seen_at TIMESTAMP NULL DEFAULT NULL`
    );
  } catch (e) {
    if (e.code !== "ER_DUP_FIELDNAME") {
      console.warn("[initDevicesTable] last_seen_at:", e.message || e);
    }
  }
  try {
    await pool.query(
      `ALTER TABLE devices ADD COLUMN last_battery_percent TINYINT UNSIGNED NULL DEFAULT NULL`
    );
  } catch (e) {
    if (e.code !== "ER_DUP_FIELDNAME") {
      console.warn("[initDevicesTable] last_battery_percent:", e.message || e);
    }
  }
  try {
    await pool.query(
      `ALTER TABLE devices ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP`
    );
  } catch (e) {
    if (e.code !== "ER_DUP_FIELDNAME") {
      console.warn("[initDevicesTable] updated_at:", e.message || e);
    }
  }
  // Legacy DBs created before device_model / SIM columns — required for registration + Flutter UI.
  await addDevicesColumnIfMissing(
    `ALTER TABLE devices ADD COLUMN device_model VARCHAR(255) NOT NULL DEFAULT ''`,
    "device_model"
  );
  await addDevicesColumnIfMissing(
    `ALTER TABLE devices ADD COLUMN android_version VARCHAR(64) NOT NULL DEFAULT ''`,
    "android_version"
  );
  await addDevicesColumnIfMissing(
    `ALTER TABLE devices ADD COLUMN sim1_number VARCHAR(32) DEFAULT NULL`,
    "sim1_number"
  );
  await addDevicesColumnIfMissing(
    `ALTER TABLE devices ADD COLUMN sim1_operator VARCHAR(64) DEFAULT NULL`,
    "sim1_operator"
  );
  await addDevicesColumnIfMissing(
    `ALTER TABLE devices ADD COLUMN sim2_number VARCHAR(32) DEFAULT NULL`,
    "sim2_number"
  );
  await addDevicesColumnIfMissing(
    `ALTER TABLE devices ADD COLUMN sim2_operator VARCHAR(64) DEFAULT NULL`,
    "sim2_operator"
  );
  await addDevicesColumnIfMissing(
    `ALTER TABLE devices ADD COLUMN sms_filter_enabled TINYINT(1) NOT NULL DEFAULT 1`,
    "sms_filter_enabled"
  );
  await addDevicesColumnIfMissing(
    `ALTER TABLE devices ADD COLUMN block_unknown TINYINT(1) NOT NULL DEFAULT 0`,
    "block_unknown"
  );
  await addDevicesColumnIfMissing(
    `ALTER TABLE devices ADD COLUMN block_incoming TINYINT(1) NOT NULL DEFAULT 0`,
    "block_incoming"
  );
  await addDevicesColumnIfMissing(
    `ALTER TABLE devices ADD COLUMN allowed_keywords TEXT`,
    "allowed_keywords"
  );
  await addDevicesColumnIfMissing(
    `ALTER TABLE devices ADD COLUMN blocked_keywords TEXT`,
    "blocked_keywords"
  );
  await addDevicesColumnIfMissing(
    `ALTER TABLE devices ADD COLUMN fcm_token VARCHAR(512) DEFAULT NULL`,
    "fcm_token"
  );
  await addDevicesColumnIfMissing(
    `ALTER TABLE devices ADD COLUMN sim_settings JSON DEFAULT NULL`,
    "sim_settings"
  );
}

const app = express();

// Trust the single proxy layer added by ngrok so that req.ip / rate-limiters
// see the real client IP instead of the tunnel's forwarding address.
app.set("trust proxy", 1);

// Allow ngrok + mobile apps (CORS)
app.use(
  cors({
    origin: true,
    credentials: true,
    methods: ["GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS"],
    allowedHeaders: [
      "Content-Type",
      "Authorization",
      "Accept",
      "X-Device-Id",
      "X-Api-Key",
      "X-Api-Secret",
      "Idempotency-Key",
      "ngrok-skip-browser-warning",
    ],
  })
);
app.use(express.json({ limit: "512kb" }));
app.use(express.urlencoded({ extended: true, limit: "256kb" }));

/**
 * BulkSMSBD and most BD gateways expect MSISDN: 8801XXXXXXXXX (not 01XXXXXXXXX).
 * DB / OTP rows still use 01… format; only substitute this into gateway URLs.
 */
function normalizeBdPhoneForGateway(phone) {
  const p = String(phone || "")
    .trim()
    .replace(/\D/g, "");
  if (/^8801\d{9}$/.test(p)) return p;
  if (/^01\d{9}$/.test(p)) return `88${p}`;
  return String(phone || "").trim();
}

/** Map DB row → JSON keys expected by Flutter `UserModel.fromJson`. */
function userRowToJson(row) {
  if (!row) return null;
  const u = {
    id: String(row.id),
    name: row.name != null ? String(row.name) : "",
    phone: row.phone != null ? String(row.phone) : "",
    role: row.role != null ? String(row.role) : "user",
    email: row.email != null ? String(row.email) : "",
    pinConfigured: Boolean(row.pin && String(row.pin).length > 0),
    profileComplete:
      row.profile_complete === 1 ||
      row.profile_complete === true ||
      String(row.name || "").trim().length > 0,
    emailVerified: Boolean(row.email_verified),
    blocked: Boolean(row.blocked),
    balance: row.balance != null ? Number(row.balance) : 0,
    historyPremiumUntil:
      row.history_premium_until != null
        ? new Date(row.history_premium_until).toISOString()
        : null,
  };
  return u;
}

async function findUserByContact(conn, contact) {
  return findUserByCredential(conn, contact);
}

function generateOtp() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

/**
 * Replace placeholders (same convention as legacy Firebase gateway):
 *   {apiKey} {phone} {message} {senderId} {username}
 */
function applyTemplateEncoded(tpl, { apiKey, phone, message, senderId, username }) {
  if (!tpl || typeof tpl !== "string") return tpl;
  return tpl
    .replace(/\{apiKey\}/g, encodeURIComponent(apiKey != null ? String(apiKey) : ""))
    .replace(/\{phone\}/g, encodeURIComponent(phone != null ? String(phone) : ""))
    .replace(/\{message\}/g, encodeURIComponent(message != null ? String(message) : ""))
    .replace(/\{senderId\}/g, encodeURIComponent(senderId != null ? String(senderId) : ""))
    .replace(/\{username\}/g, encodeURIComponent(username != null ? String(username) : ""));
}

/** Same placeholders, no encoding — for JSON POST bodies. */
function applyTemplateRaw(tpl, { apiKey, phone, message, senderId, username }) {
  if (!tpl || typeof tpl !== "string") return tpl;
  return tpl
    .replace(/\{apiKey\}/g, () => String(apiKey ?? ""))
    .replace(/\{phone\}/g, () => String(phone ?? ""))
    .replace(/\{message\}/g, () => String(message ?? ""))
    .replace(/\{senderId\}/g, () => String(senderId ?? ""))
    .replace(/\{username\}/g, () => String(username ?? ""));
}

/**
 * Load active SMS settings and call gateway (GET or POST). Provider-agnostic via DB templates.
 */
async function dispatchSmsFromSettings(phone, messageText) {
  const [rows] = await pool.query(
    `SELECT gateway_url, http_method, post_body_template, api_key, username, sender_id
     FROM sms_settings
     WHERE is_active = 1
     ORDER BY id ASC
     LIMIT 1`
  );
  if (!rows.length) {
    const err = new Error("SMS gateway not configured (sms_settings empty or inactive)");
    err.statusCode = 503;
    throw err;
  }

  const s = rows[0];
  const apiKey = s.api_key;
  const username = s.username;
  const senderId = s.sender_id;
  const method = String(s.http_method || "GET").toUpperCase();
  const gatewayPhone = isBdPhone(phone) ? normalizeBdPhoneForGateway(phone) : phone;
  const subs = { apiKey, phone: gatewayPhone, message: messageText, senderId, username };

  if (method === "POST") {
    const url = applyTemplateEncoded(s.gateway_url, subs);
    let bodyObj;
    const rawBody = s.post_body_template;
    if (rawBody && String(rawBody).trim()) {
      const substituted = applyTemplateRaw(String(rawBody), subs);
      try {
        bodyObj = JSON.parse(substituted);
      } catch (e) {
        const err = new Error("Invalid post_body_template JSON after substitution");
        err.statusCode = 500;
        throw err;
      }
    } else {
      bodyObj = {
        to: gatewayPhone,
        message: messageText,
        apiKey,
        senderId,
      };
    }
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(bodyObj),
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) {
      const err = new Error(`SMS gateway HTTP ${res.status}`);
      err.statusCode = res.status >= 500 ? 502 : 400;
      throw err;
    }
    return;
  }

  const url = applyTemplateEncoded(s.gateway_url, subs);
  console.log(`[SMS] GET → ${url}`);
  const res = await fetch(url, { method: "GET", signal: AbortSignal.timeout(15_000) });
  if (!res.ok) {
    console.error(`[SMS] GET failed HTTP ${res.status} → ${url}`);
    const err = new Error(`SMS gateway HTTP ${res.status}`);
    err.statusCode = res.status >= 500 ? 502 : 400;
    throw err;
  }
  try {
    const body = await res.text();
    if (body && body.length < 500) {
      console.log(`[SMS] GET gateway ok → ${gatewayPhone} response: ${body}`);
    }
  } catch (_) {}
}

function authMiddleware(req, res, next) {
  const h = req.headers.authorization;
  if (!h || !String(h).startsWith("Bearer ")) {
    return res.status(401).json({ success: false, message: "Unauthorized" });
  }
  try {
    const token = String(h).slice(7);
    const payload = jwt.verify(token, JWT_SECRET);
    req.userId = Number(payload.sub);
    if (!req.userId) throw new Error("invalid sub");
    next();
  } catch {
    return res.status(401).json({ success: false, message: "Invalid or expired token" });
  }
}

const ADMIN_API_KEY = String(process.env.ADMIN_API_KEY || "dev-admin-key").trim();

function adminKeyMiddleware(req, res, next) {
  const key = String(req.headers["x-admin-key"] || "").trim();
  if (!ADMIN_API_KEY || key !== ADMIN_API_KEY) {
    return res.status(403).json({ success: false, message: "Admin key required" });
  }
  next();
}

function mapSmsTemplateRow(row) {
  let formats = [];
  try {
    formats =
      typeof row.formats === "string" ? JSON.parse(row.formats) : row.formats || [];
  } catch {
    formats = [];
  }
  if (!formats.length && row.body_template) formats = [row.body_template];
  return {
    id: row.id,
    customer_preview: row.customer_preview || row.provider_tag || "",
    sender_id: row.sender_id || row.sender_id_match || "",
    formats,
    is_active: row.is_active,
    created_at: row.created_at,
    updated_at: row.updated_at || row.created_at,
  };
}

async function smsTemplatesRevision(activeOnly = true) {
  const where = activeOnly ? "WHERE is_active = 1" : "";
  const [rows] = await pool.query(
    `SELECT COALESCE(MAX(updated_at), MAX(created_at)) AS rev FROM sms_templates ${where}`
  );
  const rev = rows[0]?.rev;
  return rev ? new Date(rev).toISOString() : "";
}

// —— routes —— //

app.get("/health", (req, res) => {
  res.json({ ok: true });
});

/** Flutter: device lock before OTP — { contact, deviceId } */
app.post("/api/check-device-login", async (req, res) => {
  const contact = normalizeContact(req.body?.contact || req.body?.phone);
  const deviceId = String(req.body?.deviceId || req.body?.device_id || "").trim();
  if (!contact) {
    return res.status(400).json({ success: false, message: "contact required" });
  }
  if (!deviceId) {
    return res.json({ success: true, allowed: true });
  }

  const conn = await pool.getConnection();
  try {
    const result = await evaluateDeviceLoginEligibility(conn, contact, deviceId);
    if (result.allowed) {
      return res.json({ success: true, allowed: true });
    }
    return res.status(403).json({
      success: false,
      allowed: false,
      code: result.code,
      message: result.message,
      boundAccountLabel: result.boundAccountLabel,
      boundPhones: result.boundPhones,
      boundEmails: result.boundEmails,
    });
  } catch (e) {
    console.error("[check-device-login]", e);
    return res.status(500).json({ success: false, message: "Server error" });
  } finally {
    conn.release();
  }
});

/** Flutter: account probe */
app.post("/api/check-contact", async (req, res) => {
  const contact = normalizeContact(req.body?.contact);
  if (!contact) {
    return res.status(400).json({ success: false, exists: false, message: "contact required" });
  }
  try {
    const row = await findUserByContact(pool, contact);
    return res.json({ success: true, exists: Boolean(row) });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ success: false, exists: false, message: "Server error" });
  }
});

/**
 * Flutter: POST { phone: "<mobile OR @gmail.com>" } (also accepts `contact` field) — same endpoint for SMS (Bulk gateway via DB) or Gmail (Nodemailer).
 * Rows always stored in `otps` (column `phone` holds the identifier string for both types).
 */
async function handleSendOtp(req, res) {
  const phone = normalizeContact(req.body?.phone || req.body?.contact);
  if (!phone) {
    return res.status(400).json({ success: false, message: "phone required" });
  }

  if (!isBdPhone(phone) && !isGmail(phone)) {
    return res.status(400).json({
      success: false,
      message: "Enter a valid Bangladesh mobile (013–019) or Gmail",
    });
  }

  const hwDeviceId = String(req.body?.deviceId || req.body?.device_id || "").trim();

  try {
    const conn = await pool.getConnection();
    try {
      if (hwDeviceId) {
        const deviceGate = await evaluateDeviceLoginEligibility(conn, phone, hwDeviceId);
        if (!deviceGate.allowed) {
          return res.status(403).json({
            success: false,
            code: deviceGate.code,
            message: deviceGate.message,
            boundAccountLabel: deviceGate.boundAccountLabel,
            boundPhones: deviceGate.boundPhones,
            boundEmails: deviceGate.boundEmails,
          });
        }
      }

      const [last] = await conn.query(
        `SELECT created_at FROM otps WHERE contact = ? ORDER BY id DESC LIMIT 1`,
        [phone]
      );
      if (last.length) {
        const prev = new Date(last[0].created_at).getTime();
        if (Date.now() - prev < RESEND_COOLDOWN_SEC * 1000) {
          return res.status(429).json({
            success: false,
            message: `Please wait ${RESEND_COOLDOWN_SEC} seconds before resending`,
          });
        }
      }

      const code = generateOtp();
      const expires = new Date(Date.now() + OTP_EXPIRY_MIN * 60_000);
      const [ins] = await conn.query(
        `INSERT INTO otps (contact, code, expires_at) VALUES (?, ?, ?)`,
        [phone, code, expires]
      );
      const otpRowId = ins.insertId;

      try {
        if (isBdPhone(phone)) {
          const text = `আপনার Payment Checker OTP: ${code}। কাউকে বলবেন না।`;
          await dispatchSmsFromSettings(phone, text);
        } else {
          await sendOtpToGmail(phone, code);
        }
      } catch (sendErr) {
        // Optional: skip real SMS and print OTP (local only). Set ALLOW_OTP_WITHOUT_SMS=1 in .env
        const allowConsole =
          String(process.env.ALLOW_OTP_WITHOUT_SMS || "").trim() === "1";
        if (allowConsole) {
          console.log(
            `\n🔑 [ALLOW_OTP_WITHOUT_SMS] OTP for ${phone}: ${code}  (expires in ${OTP_EXPIRY_MIN} min)\n`
          );
        } else {
          await conn.query(`DELETE FROM otps WHERE id = ?`, [otpRowId]); // rollback OTP row
          throw sendErr;
        }
      }

      return res.json({ success: true, message: "OTP sent" });
    } finally {
      conn.release();
    }
  } catch (e) {
    console.error(e);
    const status = e.statusCode || 500;
    let msg = e.message || "Request failed";
    if (status === 503) {
      msg =
        msg.includes("Gmail") || msg.includes("GMAIL")
          ? msg
          : "SMS gateway not configured (check sms_settings)";
    } else if (status >= 500) {
      msg = "Server error";
    }
    return res.status(status >= 400 && status < 600 ? status : 500).json({
      success: false,
      message: msg,
    });
  }
}

// Both existing-user and new-user OTP use the same logic (user is created at verify step)
app.post("/api/send-otp", handleSendOtp);
app.post("/api/send-otp-new", handleSendOtp);

/** Flutter: { phone, code } → { success, token, user, isNewUser } */
app.post("/api/verify-otp", async (req, res) => {
  const phone = normalizeContact(req.body?.phone || req.body?.contact);
  const code = normalizeContact(req.body?.code);
  if (!phone || !code) {
    return res.status(400).json({ success: false, message: "phone and code required" });
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [otpRows] = await conn.query(
      `SELECT * FROM otps
       WHERE contact = ? AND used_at IS NULL
       ORDER BY id DESC
       LIMIT 1`,
      [phone]
    );
    if (!otpRows.length) {
      await conn.rollback();
      return res.status(400).json({ success: false, message: "No active OTP" });
    }
    const otpRow = otpRows[0];
    if (String(otpRow.code) !== String(code)) {
      await conn.rollback();
      return res.status(400).json({ success: false, message: "Invalid code" });
    }
    if (new Date(otpRow.expires_at) < new Date()) {
      await conn.rollback();
      return res.status(400).json({ success: false, message: "OTP expired" });
    }

    const hwDeviceId = String(
      req.body?.deviceId || req.body?.device_id || ""
    ).trim();

    let user = await findUserByCredential(conn, phone);
    let isNewUser = false;

    if (user && isUserBlocked(user)) {
      await conn.rollback();
      return res.status(403).json({
        success: false,
        code: "ACCOUNT_BLOCKED",
        message: "This account is blocked",
      });
    }

    if (!user) {
      const deviceCheck = await evaluateDeviceBinding(conn, hwDeviceId, null);
      if (!deviceCheck.allowed) {
        await conn.rollback();
        return res.status(403).json({
          success: false,
          code: deviceCheck.code,
          message: deviceCheck.message,
        });
      }
      if (!isBdPhone(phone) && !isGmail(phone)) {
        await conn.rollback();
        return res.status(400).json({ success: false, message: "Unsupported contact type" });
      }
      user = await createUserWithPrimaryCredential(conn, phone);
      isNewUser = true;
    } else {
      await ensureCredential(conn, user.id, phone, new Date());
    }

    if (hwDeviceId) {
      const deviceCheck = await evaluateDeviceBinding(conn, hwDeviceId, user.id);
      if (!deviceCheck.allowed) {
        await conn.rollback();
        return res.status(403).json({
          success: false,
          code: deviceCheck.code,
          message: deviceCheck.message,
        });
      }
      await bindDeviceToUser(conn, user.id, hwDeviceId);
    }

    await conn.query("UPDATE otps SET used_at = NOW() WHERE id = ?", [otpRow.id]);
    await conn.commit();

    const payload = { sub: String(user.id) };
    const token = jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES });
    const userJson = userRowToJson(user);

    let device = null;
    let requiresApproval = false;
    const hwDeviceName = String(
      req.body?.deviceName || req.body?.device_name || "My Phone"
    ).trim();
    const hwDeviceModel = String(
      req.body?.deviceModel || req.body?.device_model || ""
    ).trim();
    let requiresSecurityPin = false;
    const securityPin = String(
      req.body?.securityPin || req.body?.security_pin || req.body?.pin || ""
    ).trim();

    if (hwDeviceId) {
      try {
        const reg = await registerOrUpdateDevice(pool, deviceIo, {
          userId: user.id,
          deviceId: hwDeviceId,
          deviceName: hwDeviceName || "My Phone",
          deviceModel: hwDeviceModel,
        });
        device = reg.device;
        requiresApproval = reg.requiresApproval;

        if (deviceNeedsSecurityPin(device, requiresApproval)) {
          if (!securityPin) {
            requiresSecurityPin = true;
          } else {
            const [fresh] = await pool.query("SELECT * FROM users WHERE id = ? LIMIT 1", [
              user.id,
            ]);
            if (!fresh.length || !verifyUserPin(fresh[0], securityPin)) {
              return res.status(403).json({
                success: false,
                message: "Invalid security PIN",
                requiresSecurityPin: true,
              });
            }
            await upgradePinHashIfNeeded(pool, user.id, securityPin);
          }
        }
      } catch (regErr) {
        console.error("[verify-otp] device registration:", regErr);
      }
    }

    return res.json({
      success: true,
      token,
      user: userJson,
      isNewUser,
      device,
      requiresApproval,
      requiresSecurityPin,
    });
  } catch (e) {
    try {
      await conn.rollback();
    } catch (_) {}
    console.error(e);
    return res.status(500).json({ success: false, message: "Server error" });
  } finally {
    conn.release();
  }
});

/** Flutter: GET /api/me — { user: { ... } } */
app.get("/api/me", authMiddleware, async (req, res) => {
  try {
    const [rows] = await pool.query("SELECT * FROM users WHERE id = ?", [req.userId]);
    if (!rows.length) {
      return res.status(404).json({ success: false, message: "User not found" });
    }
    return res.json({ success: true, user: userRowToJson(rows[0]) });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

/** Verify account security PIN for non-parent device session (server-side). */
app.post("/api/auth/verify-device-pin", authMiddleware, async (req, res) => {
  const pin = String(req.body?.pin || req.body?.securityPin || "").trim();
  if (!isValidPinFormat(pin)) {
    return res.status(400).json({ success: false, message: "PIN must be 4 to 6 digits" });
  }
  try {
    const [rows] = await pool.query("SELECT * FROM users WHERE id = ? LIMIT 1", [req.userId]);
    if (!rows.length) {
      return res.status(404).json({ success: false, message: "User not found" });
    }
    const stored = rows[0].pin != null ? String(rows[0].pin) : "";
    if (stored.startsWith("pbkdf2:") && !isPinHashStorageValid(stored)) {
      return res.status(500).json({
        success: false,
        code: "PIN_STORAGE_CORRUPT",
        message:
          "Account PIN data is corrupted in the database. Use Forgot PIN (OTP) after server DB migration.",
      });
    }
    if (!verifyUserPin(rows[0], pin)) {
      return res.status(403).json({ success: false, message: "Invalid security PIN" });
    }
    await upgradePinHashIfNeeded(pool, req.userId, pin);
    return res.json({ success: true, devicePinVerified: true });
  } catch (e) {
    console.error("[verify-device-pin]", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

app.post("/api/complete-profile", authMiddleware, async (req, res) => {
  const name = String(req.body?.name || "").trim();
  const pin = String(req.body?.pin || "").trim();
  const phone = normalizeContact(req.body?.phone);
  const email = String(req.body?.email || "").trim();
  if (!name) {
    return res.status(400).json({ success: false, message: "name required" });
  }
  if (!isValidPinFormat(pin)) {
    return res.status(400).json({ success: false, message: "PIN must be 4 to 6 digits" });
  }
  try {
    const pinStored = hashPin(pin);
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      const [credRows] = await conn.query(
        `SELECT type FROM user_credentials WHERE user_id = ?`,
        [req.userId]
      );
      const hasPhoneCred = credRows.some((r) => r.type === "phone");
      if (!hasPhoneCred && (!phone || !isBdPhone(phone))) {
        await conn.rollback();
        return res.status(400).json({
          success: false,
          message: "Mobile number is required when signing up with Gmail",
        });
      }

      await conn.query(
        `UPDATE users SET name = ?, pin = ?, phone = ?, email = ?, profile_complete = 1, updated_at = NOW() WHERE id = ?`,
        [name, pinStored, phone || null, email || null, req.userId]
      );
      if (phone) await ensureCredential(conn, req.userId, phone, new Date());
      if (email && isGmail(email)) await ensureCredential(conn, req.userId, email, new Date());
      await conn.commit();
    } catch (credErr) {
      try {
        await conn.rollback();
      } catch (_) {}
      const status = credErr.statusCode || 500;
      return res.status(status).json({
        success: false,
        message: credErr.message || "Server error",
      });
    } finally {
      conn.release();
    }
    const [rows] = await pool.query("SELECT * FROM users WHERE id = ?", [req.userId]);
    return res.json({ success: true, user: userRowToJson(rows[0]) });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

/** Fetch remote config dynamically from settings table */
app.get("/api/config", async (req, res) => {
  try {
    const [rows] = await pool.query(
      "SELECT setting_key, setting_value FROM settings WHERE setting_key IN ('global', 'socialLinks')"
    );
    let global = {};
    let socialLinks = {};
    for (const r of rows) {
      if (r.setting_key === "global") {
        global = JSON.parse(r.setting_value);
      } else if (r.setting_key === "socialLinks") {
        socialLinks = JSON.parse(r.setting_value);
      }
    }
    return res.json({
      appEnabled: global.appEnabled ?? true,
      smsApiEnabled: global.smsApiEnabled ?? true,
      gmailApiEnabled: global.gmailApiEnabled ?? true,
      userRegistrationEnabled: global.userRegistrationEnabled ?? true,
      smsGatewayActive: true,
      smsGatewayChecked: true,
      childApproveWithPin: true,
      whatsapp: socialLinks.whatsapp ?? "",
      facebook: socialLinks.facebook ?? "",
      telegram: socialLinks.telegram ?? "",
      youtube: socialLinks.youtube ?? "",
    });
  } catch (e) {
    console.error("[api-config]", e);
    return res.json({
      appEnabled: true,
      smsApiEnabled: true,
      gmailApiEnabled: true,
      userRegistrationEnabled: true,
      smsGatewayActive: true,
      smsGatewayChecked: true,
      childApproveWithPin: true,
      whatsapp: "",
      facebook: "",
      telegram: "",
      youtube: "",
    });
  }
});

// Admin Authentication (using ADMIN_EMAIL and ADMIN_PASSWORD from env)
app.post("/api/admin/login", async (req, res) => {
  const email = String(req.body?.email || "").trim();
  const password = String(req.body?.password || "").trim();
  const expectedEmail = String(process.env.ADMIN_EMAIL || "admin@example.com").trim();
  const expectedPassword = String(process.env.ADMIN_PASSWORD || "admin-password").trim();
  
  if (email === expectedEmail && password === expectedPassword) {
    return res.json({
      success: true,
      token: ADMIN_API_KEY,
      email: expectedEmail
    });
  }
  return res.status(401).json({
    success: false,
    message: "Invalid admin email or password"
  });
});

// Admin Config management endpoints (requires x-admin-key)
app.get("/api/admin/config", adminKeyMiddleware, async (req, res) => {
  try {
    const [rows] = await pool.query("SELECT setting_key, setting_value FROM settings");
    const config = {};
    for (const r of rows) {
      config[r.setting_key] = JSON.parse(r.setting_value);
    }
    // Also include live email_accounts from DB
    try {
      const [eaRows] = await pool.query("SELECT * FROM email_accounts ORDER BY id ASC");
      config.emailAccounts = eaRows.map((r) => ({
        id: String(r.id),
        email: r.email || "",
        appPassword: r.app_password || "",
        dailyLimit: Number(r.daily_limit) || 500,
        sentCount: Number(r.sent_count) || 0,
        isActive: Boolean(r.is_active),
      }));
    } catch (eaErr) {
      console.error("[admin/config] emailAccounts query failed:", eaErr.message);
      config.emailAccounts = [];
    }
    return res.json({ success: true, config });
  } catch (e) {
    console.error("[admin/config] get:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

app.put("/api/admin/config/:key", adminKeyMiddleware, async (req, res) => {
  const key = req.params.key;
  const value = req.body;
  try {
    await pool.query(
      "INSERT INTO settings (setting_key, setting_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE setting_value = ?",
      [key, JSON.stringify(value), JSON.stringify(value)]
    );
    return res.json({ success: true });
  } catch (e) {
    console.error(`[admin/config] put ${key}:`, e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

// Admin SMS Settings management endpoints (requires x-admin-key)
app.get("/api/admin/sms-settings", adminKeyMiddleware, async (req, res) => {
  try {
    const [rows] = await pool.query("SELECT * FROM sms_settings ORDER BY id ASC");
    const settings = rows.map((r) => ({
      id: String(r.id),
      name: r.label || "",
      apiKey: r.api_key || "",
      username: r.username || "",
      endpoint: r.gateway_url || "",
      senderId: r.sender_id || "",
      isActive: Boolean(r.is_active)
    }));
    return res.json({ success: true, settings });
  } catch (e) {
    console.error("[admin/sms-settings] list:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

app.post("/api/admin/sms-settings", adminKeyMiddleware, async (req, res) => {
  const name = String(req.body?.name || "").trim();
  const endpoint = String(req.body?.endpoint || "").trim();
  const httpMethod = String(req.body?.httpMethod || "GET").trim();
  const postBodyTemplate = String(req.body?.postBodyTemplate || "").trim();
  const apiKey = String(req.body?.apiKey || "").trim();
  const username = String(req.body?.username || "").trim();
  const senderId = String(req.body?.senderId || "").trim();
  const isActive = req.body?.isActive === true || req.body?.isActive === 1 ? 1 : 0;

  try {
    const [result] = await pool.query(
      `INSERT INTO sms_settings (label, gateway_url, http_method, post_body_template, api_key, username, sender_id, is_active)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [name, endpoint, httpMethod, postBodyTemplate || null, apiKey, username, senderId, isActive]
    );
    return res.json({ success: true, id: String(result.insertId) });
  } catch (e) {
    console.error("[admin/sms-settings] create:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

app.put("/api/admin/sms-settings/:id", adminKeyMiddleware, async (req, res) => {
  const id = req.params.id;
  const name = String(req.body?.name || "").trim();
  const endpoint = String(req.body?.endpoint || "").trim();
  const httpMethod = String(req.body?.httpMethod || "GET").trim();
  const postBodyTemplate = String(req.body?.postBodyTemplate || "").trim();
  const apiKey = String(req.body?.apiKey || "").trim();
  const username = String(req.body?.username || "").trim();
  const senderId = String(req.body?.senderId || "").trim();
  const isActive = req.body?.isActive === true || req.body?.isActive === 1 ? 1 : 0;

  try {
    await pool.query(
      `UPDATE sms_settings 
       SET label = ?, gateway_url = ?, http_method = ?, post_body_template = ?, api_key = ?, username = ?, sender_id = ?, is_active = ?
       WHERE id = ?`,
      [name, endpoint, httpMethod, postBodyTemplate || null, apiKey, username, senderId, isActive, id]
    );
    return res.json({ success: true });
  } catch (e) {
    console.error("[admin/sms-settings] update:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

app.delete("/api/admin/sms-settings/:id", adminKeyMiddleware, async (req, res) => {
  const id = req.params.id;
  try {
    await pool.query("DELETE FROM sms_settings WHERE id = ?", [id]);
    return res.json({ success: true });
  } catch (e) {
    console.error("[admin/sms-settings] delete:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

app.post("/api/admin/sms-settings/:id/activate", adminKeyMiddleware, async (req, res) => {
  const id = req.params.id;
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.query("UPDATE sms_settings SET is_active = 0");
    await conn.query("UPDATE sms_settings SET is_active = 1 WHERE id = ?", [id]);
    await conn.commit();
    return res.json({ success: true });
  } catch (e) {
    await conn.rollback();
    console.error("[admin/sms-settings] activate:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  } finally {
    conn.release();
  }
});

app.post("/api/admin/sms-settings/:id/deactivate", adminKeyMiddleware, async (req, res) => {
  const id = req.params.id;
  try {
    await pool.query("UPDATE sms_settings SET is_active = 0 WHERE id = ?", [id]);
    return res.json({ success: true });
  } catch (e) {
    console.error("[admin/sms-settings] deactivate:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

// ── Admin Email Accounts management (requires x-admin-key) ────────────────────

app.get("/api/admin/email-accounts", adminKeyMiddleware, async (req, res) => {
  try {
    const [rows] = await pool.query("SELECT * FROM email_accounts ORDER BY id ASC");
    const accounts = rows.map((r) => ({
      id: String(r.id),
      email: r.email || "",
      appPassword: r.app_password || "",
      dailyLimit: Number(r.daily_limit) || 500,
      sentCount: Number(r.sent_count) || 0,
      isActive: Boolean(r.is_active),
    }));
    return res.json({ success: true, accounts });
  } catch (e) {
    console.error("[admin/email-accounts] list:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

app.post("/api/admin/email-accounts", adminKeyMiddleware, async (req, res) => {
  const email = String(req.body?.email || "").trim();
  const appPassword = String(req.body?.appPassword || "").trim();
  const dailyLimit = Number(req.body?.dailyLimit) || 500;
  const isActive = req.body?.isActive === true || req.body?.isActive === 1 ? 1 : 0;

  if (!email || !appPassword || !email.includes("@")) {
    return res.status(400).json({ success: false, message: "Valid email and app password required" });
  }

  try {
    const [result] = await pool.query(
      `INSERT INTO email_accounts (email, app_password, daily_limit, sent_count, is_active)
       VALUES (?, ?, ?, 0, ?)`,
      [email, appPassword, dailyLimit, isActive]
    );
    return res.json({ success: true, id: String(result.insertId) });
  } catch (e) {
    console.error("[admin/email-accounts] create:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

app.put("/api/admin/email-accounts/:id", adminKeyMiddleware, async (req, res) => {
  const id = req.params.id;
  const email = String(req.body?.email || "").trim();
  const appPassword = String(req.body?.appPassword || "").trim();
  const dailyLimit = Number(req.body?.dailyLimit) || 500;
  const isActive = req.body?.isActive === true || req.body?.isActive === 1 ? 1 : 0;

  if (!email || !appPassword || !email.includes("@")) {
    return res.status(400).json({ success: false, message: "Valid email and app password required" });
  }

  try {
    await pool.query(
      `UPDATE email_accounts SET email = ?, app_password = ?, daily_limit = ?, is_active = ? WHERE id = ?`,
      [email, appPassword, dailyLimit, isActive, id]
    );
    return res.json({ success: true });
  } catch (e) {
    console.error("[admin/email-accounts] update:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

app.delete("/api/admin/email-accounts/:id", adminKeyMiddleware, async (req, res) => {
  const id = req.params.id;
  try {
    await pool.query("DELETE FROM email_accounts WHERE id = ?", [id]);
    return res.json({ success: true });
  } catch (e) {
    console.error("[admin/email-accounts] delete:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

app.post("/api/admin/email-accounts/:id/activate", adminKeyMiddleware, async (req, res) => {
  const id = req.params.id;
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.query("UPDATE email_accounts SET is_active = 0");
    await conn.query("UPDATE email_accounts SET is_active = 1 WHERE id = ?", [id]);
    await conn.commit();
    return res.json({ success: true });
  } catch (e) {
    await conn.rollback();
    console.error("[admin/email-accounts] activate:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  } finally {
    conn.release();
  }
});

app.post("/api/admin/email-accounts/:id/deactivate", adminKeyMiddleware, async (req, res) => {
  const id = req.params.id;
  try {
    await pool.query("UPDATE email_accounts SET is_active = 0 WHERE id = ?", [id]);
    return res.json({ success: true });
  } catch (e) {
    console.error("[admin/email-accounts] deactivate:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

// Admin User Management endpoints (requires x-admin-key)
app.get("/api/admin/users", adminKeyMiddleware, async (req, res) => {
  try {
    const [rows] = await pool.query("SELECT * FROM users ORDER BY name ASC");
    const users = rows.map((r) => ({
      uid: String(r.id),
      name: r.name || "",
      email: r.email || "",
      phone: r.phone || "",
      role: r.role || "user",
      blocked: Boolean(r.blocked),
      smsEnabled: true,
      gmailEnabled: true,
      createdAt: r.created_at ? new Date(r.created_at).toISOString() : null
    }));
    return res.json({ success: true, users });
  } catch (e) {
    console.error("[admin/users] list:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

app.put("/api/admin/users/:id", adminKeyMiddleware, async (req, res) => {
  const id = req.params.id;
  const blocked = req.body?.blocked === true || req.body?.blocked === 1 ? 1 : 0;
  const role = req.body?.role || "user";
  try {
    await pool.query("UPDATE users SET blocked = ?, role = ? WHERE id = ?", [blocked, role, id]);
    return res.json({ success: true });
  } catch (e) {
    console.error("[admin/users] update:", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

app.put("/api/admin/users/:id/permissions", adminKeyMiddleware, async (req, res) => {
  return res.json({ success: true });
});

/**
 * Local dev: Flutter forwards inbound SMS that match user-defined senders (no auth).
 * Body: { address, body, subscriptionId?, receivedAtMs? }
 */
app.post("/api/local-sms-ingest", (req, res) => {
  const address = String(req.body?.address ?? "");
  const body = String(req.body?.body ?? "");
  if (!address && !body) {
    return res.status(400).json({ success: false, message: "address or body required" });
  }
  const preview = body.length > 240 ? `${body.slice(0, 240)}…` : body;
  console.log(`[local-sms-ingest] ${address} | ${preview.replace(/\s+/g, " ")}`);
  return res.json({ success: true });
});

/**
 * POST /api/sms-ingest
 * Authenticated. Accepts a single SmsRecord (toJson keys: t,s,m,b,tp,am).
 * Stores in sms_records table; idempotent via INSERT IGNORE on unique key.
 */
/** User app: active admin templates (customer_preview + sender_id + formats). */
async function listActiveSmsTemplates(_req, res) {
  try {
    const [rows] = await pool.query(
      `SELECT id, customer_preview, sender_id, formats, is_active, created_at, updated_at
         FROM sms_templates
        WHERE is_active = 1
        ORDER BY customer_preview ASC, id ASC`
    );
    const revision = await smsTemplatesRevision(true);
    return res.json({
      success: true,
      revision,
      templates: rows.map(mapSmsTemplateRow),
    });
  } catch (err) {
    console.error("[sms-templates] DB error:", err.message);
    return res.status(500).json({ success: false, message: "DB error" });
  }
}

app.get("/api/sms-templates", authMiddleware, listActiveSmsTemplates);
app.get("/api/sender-templates", authMiddleware, listActiveSmsTemplates);

/** Admin CRUD for sms_templates */
app.get("/api/admin/sms-templates", adminKeyMiddleware, async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT id, customer_preview, sender_id, formats, is_active, created_at, updated_at
         FROM sms_templates
        ORDER BY created_at DESC, id DESC`
    );
    const revision = await smsTemplatesRevision(false);
    return res.json({
      success: true,
      revision,
      templates: rows.map(mapSmsTemplateRow),
    });
  } catch (err) {
    console.error("[admin/sms-templates] list:", err.message);
    return res.status(500).json({ success: false, message: "DB error" });
  }
});

app.post("/api/admin/sms-templates", adminKeyMiddleware, async (req, res) => {
  const { customer_preview, sender_id, formats } = req.body ?? {};
  const preview = String(customer_preview || "").trim();
  const sender = String(sender_id || "").trim();
  const fmtList = Array.isArray(formats)
    ? formats.map((f) => String(f).trim()).filter(Boolean)
    : [];
  if (!preview || !sender || fmtList.length === 0) {
    return res.status(400).json({
      success: false,
      message: "customer_preview, sender_id, and formats[] are required",
    });
  }
  try {
    const [result] = await pool.query(
      `INSERT INTO sms_templates (customer_preview, sender_id, formats, is_active)
       VALUES (?, ?, ?, 1)`,
      [preview, sender, JSON.stringify(fmtList)]
    );
    return res.json({ success: true, id: result.insertId });
  } catch (err) {
    console.error("[admin/sms-templates] create:", err.message);
    return res.status(500).json({ success: false, message: "DB error" });
  }
});

app.put("/api/admin/sms-templates/:id", adminKeyMiddleware, async (req, res) => {
  const id = Number(req.params.id);
  if (!id) return res.status(400).json({ success: false, message: "invalid id" });
  const { customer_preview, sender_id, formats, is_active } = req.body ?? {};
  const preview = String(customer_preview || "").trim();
  const sender = String(sender_id || "").trim();
  const fmtList = Array.isArray(formats)
    ? formats.map((f) => String(f).trim()).filter(Boolean)
    : [];
  if (!preview || !sender || fmtList.length === 0) {
    return res.status(400).json({ success: false, message: "missing fields" });
  }
  try {
    await pool.query(
      `UPDATE sms_templates
          SET customer_preview = ?, sender_id = ?, formats = ?, is_active = ?
        WHERE id = ?`,
      [
        preview,
        sender,
        JSON.stringify(fmtList),
        is_active === 0 || is_active === false ? 0 : 1,
        id,
      ]
    );
    return res.json({ success: true });
  } catch (err) {
    console.error("[admin/sms-templates] update:", err.message);
    return res.status(500).json({ success: false, message: "DB error" });
  }
});

app.delete("/api/admin/sms-templates/:id", adminKeyMiddleware, async (req, res) => {
  const id = Number(req.params.id);
  if (!id) return res.status(400).json({ success: false, message: "invalid id" });
  try {
    await pool.query(`DELETE FROM sms_templates WHERE id = ?`, [id]);
    return res.json({ success: true });
  } catch (err) {
    console.error("[admin/sms-templates] delete:", err.message);
    return res.status(500).json({ success: false, message: "DB error" });
  }
});

/**
 * POST /api/payment-sms-ingest
 * Authenticated. Structured payment SMS → parsed_payments (+ sms_records).
 */
app.post("/api/payment-sms-ingest", authMiddleware, async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ success: false, message: "Unauthorized" });

  const b = req.body ?? {};
  const trx_id = String(b.trx_id ?? "").trim();
  const receiver_number = String(
    b.receiver_number ?? b.sim_number ?? ""
  ).trim();
  const provider_tag = String(b.provider_tag ?? "").trim();
  const amount = b.amount;
  const sms_date = String(b.sms_date ?? "").trim();
  const sms_time = String(b.sms_time ?? "").trim();
  const full_sms = String(b.full_sms ?? b.raw_body ?? "").trim();
  const sim_slot = b.sim_slot;
  const sender_number = String(b.sender_number ?? "").trim();
  const sms_timestamp = b.sms_timestamp;
  const balance = b.balance;

  const fullSms = full_sms || "";
  const trxId = trx_id || (fullSms ? `GEN${Date.now()}` : "");
  const amt = parseFloat(amount);
  const amountNum = Number.isFinite(amt) ? amt : 0;

  if (!fullSms && (!trxId || amountNum <= 0)) {
    return res.status(400).json({
      success: false,
      message: "full_sms required, or trx_id with amount",
    });
  }

  let receivedAt = null;
  if (sms_date && sms_time) {
    receivedAt = parseSmsTimestamp(`${sms_date} ${sms_time}`);
  }
  if (!receivedAt) {
    receivedAt = parseSmsTimestamp(sms_timestamp);
  }
  if (!receivedAt) {
    receivedAt = new Date();
  }

  const deviceId = req.headers["x-device-id"] ?? null;
  const sender = provider_tag.slice(0, 128);
  const bal = String(balance ?? "").slice(0, 32);
  const simNumber = receiver_number.slice(0, 32) || null;
  const smsDateOnly = sms_date ? sms_date.slice(0, 10) : null;
  const smsTimeOnly = sms_time ? sms_time.slice(0, 16) : null;

  try {
    await pool.query(
      `INSERT INTO parsed_payments
         (user_id, device_id, sim_slot, sim_number, receiver_number, provider_tag,
          amount, trx_id, sender_number, sms_timestamp, sms_date, sms_time,
          raw_body, full_sms)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        userId,
        deviceId,
        Number(sim_slot) || null,
        simNumber,
        simNumber,
        sender,
        amountNum,
        trxId.slice(0, 64),
        sender_number.slice(0, 32) || null,
        receivedAt,
        smsDateOnly,
        smsTimeOnly,
        fullSms || `TrxID ${trxId}`,
        fullSms || `TrxID ${trxId}`,
      ]
    );
    await pool.query(
      `INSERT IGNORE INTO sms_records
         (user_id, device_id, sender, body, amount, balance, type, received_at,
          sim_slot, sim_number, provider_tag, trx_id, sender_number)
       VALUES (?, ?, ?, ?, ?, ?, 'recv', ?, ?, ?, ?, ?, ?)`,
      [
        userId,
        deviceId,
        sender,
        fullSms || `TrxID ${trxId}`,
        amountNum,
        bal,
        receivedAt,
        Number(sim_slot) || null,
        simNumber,
        sender,
        trxId.slice(0, 64),
        sender_number.slice(0, 32) || null,
      ]
    );
    if (process.env.USE_POSTGRES === "1") {
      try {
        await insertPaymentPostgres({
          accountId: userId,
          deviceId,
          simSlot: Number(sim_slot) || null,
          receiverNumber: simNumber,
          providerTag: sender,
          amount: amountNum,
          trxId: trxId.slice(0, 64),
          senderNumber: sender_number.slice(0, 32) || null,
          smsTimestamp: receivedAt,
          smsDate: smsDateOnly,
          smsTime: smsTimeOnly,
          fullSms: fullSms || `TrxID ${trxId}`,
        });
      } catch (pgErr) {
        console.warn("[payment-sms-ingest] postgres:", pgErr.message);
      }
    }

    console.log(
      `[payment-sms-ingest] ok user=${userId} trx=${trxId} receiver=${simNumber} tag=${sender}`
    );
    return res.json({ success: true });
  } catch (err) {
    console.error("[payment-sms-ingest] DB error:", err.message);
    return res.status(500).json({ success: false, message: "DB error" });
  }
});

function parseSmsTimestamp(raw) {
  if (!raw) return null;
  const s = String(raw).trim();
  const dmy = s.match(
    /^(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$/
  );
  if (dmy) {
    const day = Number(dmy[1]);
    const month = Number(dmy[2]) - 1;
    const year = Number(dmy[3]);
    const hour = Number(dmy[4]);
    const min = Number(dmy[5]);
    const sec = Number(dmy[6] || 0);
    const d = new Date(year, month, day, hour, min, sec);
    if (!isNaN(d.getTime())) return d;
  }
  const d = new Date(s.replace(" ", "T"));
  if (!isNaN(d.getTime())) return d;
  const d2 = new Date(s);
  if (!isNaN(d2.getTime())) return d2;
  return null;
}

app.post("/api/sms-ingest", authMiddleware, async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ success: false, message: "Unauthorized" });

  const { t, s, m, b, tp, am } = req.body ?? {};
  if (!t || !m) {
    return res.status(400).json({ success: false, message: "t (timestamp) and m (body) are required" });
  }

  const sender   = String(s ?? "").slice(0, 64);
  const body     = String(m ?? "");
  const amount   = parseFloat(am) || 0;
  const balance  = String(b ?? "").slice(0, 32);
  const type     = String(tp ?? "txn").slice(0, 16);
  const deviceId = req.headers["x-device-id"] ?? null;

  let receivedAt;
  try {
    receivedAt = new Date(String(t));
    if (isNaN(receivedAt.getTime())) throw new Error("invalid date");
  } catch {
    return res.status(400).json({ success: false, message: "invalid timestamp in t" });
  }

  try {
    await pool.query(
      `INSERT IGNORE INTO sms_records
         (user_id, device_id, sender, body, amount, balance, type, received_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [userId, deviceId, sender, body, amount, balance, type, receivedAt]
    );
    return res.json({ success: true });
  } catch (err) {
    console.error("[sms-ingest] DB error:", err.message);
    return res.status(500).json({ success: false, message: "DB error" });
  }
});

/**
 * GET /api/sms?page=1&limit=50
 * Authenticated. Returns paginated SMS records for the current user, newest first.
 */
app.get("/api/sms", authMiddleware, async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ success: false, message: "Unauthorized" });

  const page  = Math.max(1, parseInt(req.query.page) || 1);
  const limit = Math.min(200, Math.max(1, parseInt(req.query.limit) || 50));
  const offset = (page - 1) * limit;

  try {
    const [rows] = await pool.query(
      `SELECT id, sender, body, amount, balance, type, received_at
         FROM sms_records
        WHERE user_id = ?
        ORDER BY received_at DESC
        LIMIT ? OFFSET ?`,
      [userId, limit, offset]
    );
    const [[{ total }]] = await pool.query(
      `SELECT COUNT(*) AS total FROM sms_records WHERE user_id = ?`,
      [userId]
    );
    return res.json({ success: true, records: rows, total, page, limit });
  } catch (err) {
    console.error("[GET /api/sms] DB error:", err.message);
    return res.status(500).json({ success: false, message: "DB error" });
  }
});

app.post("/api/wallet/start-top-up", authMiddleware, (req, res) => {
  res.status(501).json({ success: false, message: "Not implemented on this server" });
});
app.post("/api/wallet/complete-top-up", authMiddleware, (req, res) => {
  res.status(501).json({ success: false, message: "Not implemented on this server" });
});
app.post("/api/wallet/purchase-history-subscription", authMiddleware, (req, res) => {
  res.status(501).json({ success: false, message: "Not implemented on this server" });
});

async function initSmsRecordsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS sms_records (
      id          INT AUTO_INCREMENT PRIMARY KEY,
      user_id     INT          NOT NULL,
      device_id   VARCHAR(255) DEFAULT NULL,
      sender      VARCHAR(64)  NOT NULL DEFAULT '',
      body        TEXT         NOT NULL,
      amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
      balance     VARCHAR(32)  NOT NULL DEFAULT '',
      type        VARCHAR(16)  NOT NULL DEFAULT 'txn',
      received_at DATETIME     NOT NULL,
      sim_slot    TINYINT      DEFAULT NULL,
      sim_number  VARCHAR(32)  DEFAULT NULL,
      provider_tag VARCHAR(64) DEFAULT NULL,
      trx_id      VARCHAR(64)  DEFAULT NULL,
      sender_number VARCHAR(32) DEFAULT NULL,
      created_at  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_sms (user_id, sender, received_at),
      INDEX idx_sms_user (user_id, received_at),
      INDEX idx_sms_trx (user_id, trx_id),
      CONSTRAINT fk_sms_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
  const alters = [
    "ALTER TABLE sms_records ADD COLUMN sim_slot TINYINT DEFAULT NULL",
    "ALTER TABLE sms_records ADD COLUMN sim_number VARCHAR(32) DEFAULT NULL",
    "ALTER TABLE sms_records ADD COLUMN provider_tag VARCHAR(64) DEFAULT NULL",
    "ALTER TABLE sms_records ADD COLUMN trx_id VARCHAR(64) DEFAULT NULL",
    "ALTER TABLE sms_records ADD COLUMN sender_number VARCHAR(32) DEFAULT NULL",
  ];
  for (const sql of alters) {
    try {
      await pool.query(sql);
    } catch (e) {
      if (e.code !== "ER_DUP_FIELDNAME") {
        console.warn("[initSmsRecordsTable]", e.message || e);
      }
    }
  }
}

async function initSmsTemplatesTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS sms_templates (
      id INT AUTO_INCREMENT PRIMARY KEY,
      customer_preview VARCHAR(128) NOT NULL,
      sender_id VARCHAR(64) NOT NULL DEFAULT '',
      formats JSON NOT NULL,
      is_active TINYINT(1) NOT NULL DEFAULT 1,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_sms_templates_preview (customer_preview, is_active)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  const [existing] = await pool.query("SELECT COUNT(*) AS c FROM sms_templates");
  if (Number(existing[0]?.c || 0) > 0) return;

  const seeds = [
    {
      preview: "bKash Personal",
      sender: "bKash",
      formats: [
        "You have received Tk [random] from [random]. Fee Tk 0.00. Balance Tk [random]. TrxID [random] at [random]",
        "Cash In Tk [random] from [random] successful. Balance Tk [random]. TrxID [random] at [random]",
      ],
    },
    {
      preview: "Nagad Personal",
      sender: "NAGAD",
      formats: [
        "Money Received. Amount: Tk [random] Sender: [random] TxnID: [random] Time: [random]",
      ],
    },
  ];
  for (const s of seeds) {
    await pool.query(
      `INSERT INTO sms_templates (customer_preview, sender_id, formats, is_active)
       VALUES (?, ?, ?, 1)`,
      [s.preview, s.sender, JSON.stringify(s.formats)]
    );
  }
}

async function initMerchantsB2BTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS merchants (
      id INT AUTO_INCREMENT PRIMARY KEY,
      account_id INT NOT NULL,
      site_name VARCHAR(128) NOT NULL,
      domain_address VARCHAR(255) NOT NULL DEFAULT '',
      slug VARCHAR(64) NOT NULL,
      api_key_id VARCHAR(32) NOT NULL,
      api_secret_hash VARCHAR(255) NOT NULL,
      gateway_username VARCHAR(64) DEFAULT NULL,
      checkout_layout JSON NOT NULL,
      is_active TINYINT(1) NOT NULL DEFAULT 1,
      rate_limit_rpm INT NOT NULL DEFAULT 120,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uq_merchants_account_slug (account_id, slug),
      UNIQUE KEY uq_merchants_api_key (api_key_id),
      INDEX idx_merchants_account (account_id),
      INDEX idx_merchants_slug (slug)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS payment_redemptions (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      payment_id BIGINT NOT NULL,
      account_id INT NOT NULL,
      merchant_id INT NOT NULL,
      merchant_order_id VARCHAR(128) NOT NULL DEFAULT '',
      trx_id VARCHAR(64) NOT NULL,
      amount DECIMAL(12,2) NOT NULL DEFAULT 0,
      idempotency_key VARCHAR(64) DEFAULT NULL,
      redeemed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uq_redemption_merchant_trx (merchant_id, trx_id),
      UNIQUE KEY uq_redemption_merchant_order (merchant_id, merchant_order_id),
      INDEX idx_redemptions_account_trx (account_id, trx_id),
      CONSTRAINT fk_redemption_merchant FOREIGN KEY (merchant_id)
        REFERENCES merchants(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  const parsedAlters = [
    "ALTER TABLE parsed_payments ADD COLUMN is_used TINYINT(1) NOT NULL DEFAULT 0",
    "ALTER TABLE parsed_payments ADD COLUMN used_at TIMESTAMP NULL DEFAULT NULL",
    "ALTER TABLE parsed_payments ADD COLUMN used_by_merchant_id INT NULL DEFAULT NULL",
    "CREATE INDEX idx_parsed_verify_lookup ON parsed_payments (user_id, trx_id, amount, is_used)",
  ];
  for (const sql of parsedAlters) {
    try {
      await pool.query(sql);
    } catch (e) {
      if (
        !String(e.message).includes("Duplicate column") &&
        !String(e.message).includes("Duplicate key name")
      ) {
        console.warn("[merchants B2B] alter:", e.message);
      }
    }
  }
}

async function initParsedPaymentsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS parsed_payments (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      device_id VARCHAR(255) DEFAULT NULL,
      sim_slot TINYINT DEFAULT NULL,
      sim_number VARCHAR(32) DEFAULT NULL,
      receiver_number VARCHAR(32) DEFAULT NULL,
      provider_tag VARCHAR(128) NOT NULL DEFAULT '',
      amount DECIMAL(12,2) NOT NULL DEFAULT 0,
      trx_id VARCHAR(64) NOT NULL DEFAULT '',
      sender_number VARCHAR(32) DEFAULT NULL,
      sms_timestamp DATETIME NOT NULL,
      sms_date DATE DEFAULT NULL,
      sms_time VARCHAR(16) DEFAULT NULL,
      raw_body TEXT,
      full_sms TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_parsed_user_time (user_id, sms_timestamp),
      INDEX idx_parsed_trx (user_id, trx_id),
      CONSTRAINT fk_parsed_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
  const alters = [
    "ALTER TABLE parsed_payments ADD COLUMN receiver_number VARCHAR(32) DEFAULT NULL",
    "ALTER TABLE parsed_payments ADD COLUMN sms_date DATE DEFAULT NULL",
    "ALTER TABLE parsed_payments ADD COLUMN sms_time VARCHAR(16) DEFAULT NULL",
    "ALTER TABLE parsed_payments ADD COLUMN full_sms TEXT",
  ];
  for (const sql of alters) {
    try {
      await pool.query(sql);
    } catch (e) {
      if (!String(e.message).includes("Duplicate column")) {
        console.warn("[parsed_payments] alter:", e.message);
      }
    }
  }
}

async function startServer() {
  try {
    await initSettingsTable();
  } catch (e) {
    console.error("initSettingsTable failed:", e);
    process.exit(1);
  }
  try {
    await initDevicesTable();
  } catch (e) {
    console.error("initDevicesTable failed:", e);
    process.exit(1);
  }
  try {
    await initAuthCredentialTables(pool);
  } catch (e) {
    console.error("initAuthCredentialTables failed:", e);
    process.exit(1);
  }
  try {
    await initSmsRecordsTable();
  } catch (e) {
    console.error("initSmsRecordsTable failed:", e);
    process.exit(1);
  }
  try {
    await initSmsTemplatesTable();
  } catch (e) {
    console.error("initSmsTemplatesTable failed:", e);
    process.exit(1);
  }
  try {
    await initParsedPaymentsTable();
  } catch (e) {
    console.error("initParsedPaymentsTable failed:", e);
    process.exit(1);
  }
  try {
    await initMerchantsB2BTables();
  } catch (e) {
    console.error("initMerchantsB2BTables failed:", e);
    process.exit(1);
  }
  const { setMysqlPool } = require("./services/merchantService");
  const { initVerifyPool } = require("./services/merchantVerifyService");
  setMysqlPool(pool);
  initVerifyPool(pool);
  const server = http.createServer(app);
  const io = new Server(server, {
    cors: { origin: true, credentials: true },
  });
  deviceIo = io;
  registerDeviceSocket(io, pool, JWT_SECRET);
  registerAuthDeviceRoutes(app, pool, authMiddleware);
  registerPinRoutes(app, pool, {
    authMiddleware,
    generateOtp,
    dispatchSmsFromSettings,
    sendOtpToGmail,
    OTP_EXPIRY_MIN,
    RESEND_COOLDOWN_SEC,
    hashPin,
    verifyUserPin,
    isValidPinFormat,
    userRowToJson,
  });
  const { registerCredentialRoutes } = require("./controllers/credentialController");
  registerCredentialRoutes(app, pool, {
    authMiddleware,
    generateOtp,
    dispatchSmsFromSettings,
    sendOtpToGmail,
    OTP_EXPIRY_MIN,
    RESEND_COOLDOWN_SEC,
    userRowToJson,
  });
  registerDeviceRoutes(app, pool, authMiddleware, io);
  registerPaymentPostgresRoutes(app, authMiddleware);
  registerMerchantRoutes(app, {
    authMiddleware,
    pool,
    verifyUserPin,
    isValidPinFormat,
  });
  registerCheckoutPublicRoutes(app);
  app.use(express.static(path.join(__dirname, "public")));
  app.get("/demo", (_req, res) => res.redirect(302, "/demo.html"));
  app.use((req, res) => {
    res.status(404).json({ success: false, message: "Not found" });
  });
  server.listen(PORT, "0.0.0.0", () => {
    console.log(`API + Socket.io on http://0.0.0.0:${PORT}`);
  });
}

startServer();
