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
const express = require("express");
const cors = require("cors");
const mysql = require("mysql2/promise");
const jwt = require("jsonwebtoken");
const nodemailer = require("nodemailer");

const PORT = Number(process.env.PORT || 3000);
const JWT_SECRET = process.env.JWT_SECRET || "change-me-in-production";
const JWT_EXPIRES = process.env.JWT_EXPIRES || "30d";
const OTP_EXPIRY_MIN = Number(process.env.OTP_EXPIRY_MIN || 10);
const RESEND_COOLDOWN_SEC = Number(process.env.OTP_RESEND_COOLDOWN_SEC || 60);

/** Gmail account that sends OTP mail (App Password in GMAIL_APP_PASSWORD). */
const GMAIL_USER = process.env.GMAIL_USER || "";
const GMAIL_APP_PASSWORD = String(
  process.env.GMAIL_APP_PASSWORD || ""
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

/**
 * Send 6-digit OTP to the user's Gmail (same `otps.phone` column stores the address string).
 */
async function sendOtpToGmail(toAddress, code) {
  const transport = getGmailTransport();
  if (!transport) {
    const err = new Error(
      "Gmail OTP not configured: set GMAIL_USER and GMAIL_APP_PASSWORD in .env"
    );
    err.statusCode = 503;
    throw err;
  }
  const from = process.env.GMAIL_FROM || GMAIL_USER;
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

const pool = mysql.createPool({
  host: process.env.DB_HOST || "127.0.0.1",
  user: process.env.DB_USER || "root",
  password: process.env.DB_PASSWORD || "",
  database: process.env.DB_NAME || "payment_checker",
  waitForConnections: true,
  connectionLimit: 10,
});

const app = express();
// Flutter Web (localhost:any) + mobile apps — reflect Origin so browser CORS accepts API calls
app.use(
  cors({
    origin: true,
    credentials: true,
    methods: ["GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization", "Accept"],
  })
);
app.use(express.json({ limit: "512kb" }));

function isBdPhone(s) {
  return /^(013|014|015|016|017|018|019)\d{8}$/.test(String(s || ""));
}

function isGmail(s) {
  return /^[^\s@]+@gmail\.com$/i.test(String(s || ""));
}

function normalizeContact(raw) {
  return String(raw || "").trim();
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
    pin: row.pin != null ? String(row.pin) : "",
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
  const c = normalizeContact(contact);
  const [rows] = await conn.query(
    "SELECT * FROM users WHERE phone = ? OR email = ? LIMIT 1",
    [c, c]
  );
  return rows[0] || null;
}

function generateOtp() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

/**
 * Replace placeholders (same convention as legacy Firebase gateway):
 *   {apiKey} {phone} {message} {senderId}
 */
function applyTemplateEncoded(tpl, { apiKey, phone, message, senderId }) {
  if (!tpl || typeof tpl !== "string") return tpl;
  return tpl
    .replace(/\{apiKey\}/g, encodeURIComponent(apiKey != null ? String(apiKey) : ""))
    .replace(/\{phone\}/g, encodeURIComponent(phone != null ? String(phone) : ""))
    .replace(/\{message\}/g, encodeURIComponent(message != null ? String(message) : ""))
    .replace(/\{senderId\}/g, encodeURIComponent(senderId != null ? String(senderId) : ""));
}

/** Same placeholders, no encoding — for JSON POST bodies. */
function applyTemplateRaw(tpl, { apiKey, phone, message, senderId }) {
  if (!tpl || typeof tpl !== "string") return tpl;
  return tpl
    .replace(/\{apiKey\}/g, () => String(apiKey ?? ""))
    .replace(/\{phone\}/g, () => String(phone ?? ""))
    .replace(/\{message\}/g, () => String(message ?? ""))
    .replace(/\{senderId\}/g, () => String(senderId ?? ""));
}

/**
 * Load active SMS settings and call gateway (GET or POST). Provider-agnostic via DB templates.
 */
async function dispatchSmsFromSettings(phone, messageText) {
  const [rows] = await pool.query(
    `SELECT gateway_url, http_method, post_body_template, api_key, sender_id
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
  const senderId = s.sender_id;
  const method = String(s.http_method || "GET").toUpperCase();
  const subs = { apiKey, phone, message: messageText, senderId };

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
        to: phone,
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
  const res = await fetch(url, { method: "GET", signal: AbortSignal.timeout(15_000) });
  if (!res.ok) {
    const err = new Error(`SMS gateway HTTP ${res.status}`);
    err.statusCode = res.status >= 500 ? 502 : 400;
    throw err;
  }
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

// —— routes —— //

app.get("/health", (req, res) => {
  res.json({ ok: true });
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
 * Flutter: POST { phone: "<mobile OR @gmail.com>" } — same endpoint for SMS (Bulk gateway via DB) or Gmail (Nodemailer).
 * Rows always stored in `otps` (column `phone` holds the identifier string for both types).
 */
app.post("/api/send-otp", async (req, res) => {
  const phone = normalizeContact(req.body?.phone);
  if (!phone) {
    return res.status(400).json({ success: false, message: "phone required" });
  }

  if (!isBdPhone(phone) && !isGmail(phone)) {
    return res.status(400).json({
      success: false,
      message: "Enter a valid Bangladesh mobile (013–019) or Gmail",
    });
  }

  try {
    const conn = await pool.getConnection();
    try {
      const [last] = await conn.query(
        `SELECT created_at FROM otps WHERE phone = ? ORDER BY id DESC LIMIT 1`,
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
        `INSERT INTO otps (phone, code, expires_at) VALUES (?, ?, ?)`,
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
        await conn.query(`DELETE FROM otps WHERE id = ?`, [otpRowId]);
        throw sendErr;
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
});

/** Flutter: { phone, code } → { success, token, user, isNewUser } */
app.post("/api/verify-otp", async (req, res) => {
  const phone = normalizeContact(req.body?.phone);
  const code = normalizeContact(req.body?.code);
  if (!phone || !code) {
    return res.status(400).json({ success: false, message: "phone and code required" });
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [otpRows] = await conn.query(
      `SELECT * FROM otps
       WHERE phone = ? AND used_at IS NULL
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

    let user = await findUserByContact(conn, phone);
    let isNewUser = false;
    if (!user) {
      let insPhone = null;
      let insEmail = null;
      if (isBdPhone(phone)) insPhone = phone;
      else if (isGmail(phone)) insEmail = phone;
      else {
        await conn.rollback();
        return res.status(400).json({ success: false, message: "Unsupported contact type" });
      }
      const [r] = await conn.query(
        `INSERT INTO users (phone, email, name, role) VALUES (?, ?, '', 'user')`,
        [insPhone, insEmail]
      );
      const [inserted] = await conn.query("SELECT * FROM users WHERE id = ?", [r.insertId]);
      user = inserted[0];
      isNewUser = true;
    }

    await conn.query("UPDATE otps SET used_at = NOW() WHERE id = ?", [otpRow.id]);
    await conn.commit();

    const payload = { sub: String(user.id) };
    const token = jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES });
    const userJson = userRowToJson(user);

    return res.json({
      success: true,
      token,
      user: userJson,
      isNewUser,
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

app.post("/api/complete-profile", authMiddleware, async (req, res) => {
  const name = String(req.body?.name || "").trim();
  const pin = String(req.body?.pin || "");
  const phone = normalizeContact(req.body?.phone);
  const email = String(req.body?.email || "").trim();
  if (!name) {
    return res.status(400).json({ success: false, message: "name required" });
  }
  try {
    await pool.query(
      `UPDATE users SET name = ?, pin = ?, phone = ?, email = ?, updated_at = NOW() WHERE id = ?`,
      [name, pin, phone || null, email || null, req.userId]
    );
    const [rows] = await pool.query("SELECT * FROM users WHERE id = ?", [req.userId]);
    return res.json({ success: true, user: userRowToJson(rows[0]) });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

/** Minimal stub so Flutter `fetchRemoteConfig` does not break */
app.get("/api/config", (req, res) => {
  res.json({
    appEnabled: true,
    smsApiEnabled: true,
    gmailApiEnabled: true,
    userRegistrationEnabled: true,
    smsGatewayActive: true,
    smsGatewayChecked: true,
    whatsapp: "",
    facebook: "",
    telegram: "",
    youtube: "",
  });
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

app.use((req, res) => {
  res.status(404).json({ success: false, message: "Not found" });
});

app.listen(PORT, () => {
  console.log(`API listening on http://0.0.0.0:${PORT}`);
});
