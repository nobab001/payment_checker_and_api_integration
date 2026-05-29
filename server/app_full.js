/**
 * Payment Checker OTP System
 * Complete rewrite - .env only configuration
 * 
 * Endpoints:
 * - POST /api/check-contact  : Check if contact exists
 * - POST /api/send-otp      : For EXISTING users only
 * - POST /api/send-otp-new  : For NEW users (creates user + sends OTP)
 * - POST /api/verify-otp    : Verify OTP and get JWT token
 */

require("dotenv").config();
const express = require("express");
const mysql = require("mysql2/promise");
const nodemailer = require("nodemailer");
const axios = require("axios");
const jwt = require("jsonwebtoken");
const rateLimit = require("express-rate-limit");
const helmet = require("helmet");
const cors = require("cors");

const app = express();

// ============================================================
// CONFIGURATION (ALL from .env)
// ============================================================

const CONFIG = {
  // ===== Database =====
  DB_HOST: process.env.DB_HOST || "localhost",
  DB_PORT: parseInt(process.env.DB_PORT) || 3306,
  DB_USER: process.env.DB_USER || "root",
  DB_PASSWORD: process.env.DB_PASSWORD || "",
  DB_NAME: process.env.DB_NAME || "payment_checker",

  // ===== JWT =====
  JWT_SECRET: process.env.JWT_SECRET || "change-this-secret-in-production",
  JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN || "7d",

  // ===== OTP Settings =====
  OTP_LENGTH: parseInt(process.env.OTP_LENGTH) || 6,
  OTP_EXPIRY_MINUTES: parseInt(process.env.OTP_EXPIRY_MINUTES) || 5,
  OTP_RESEND_COOLDOWN_SEC: parseInt(process.env.OTP_RESEND_COOLDOWN_SEC) || 60,

  // ===== Gmail/Nodemailer =====
  GMAIL_USER: process.env.GMAIL_USER || "",
  GMAIL_PASS: process.env.GMAIL_PASS || "",
  GMAIL_FROM: process.env.GMAIL_FROM || "",
  GMAIL_OTP_SUBJECT: process.env.GMAIL_OTP_SUBJECT || "Payment Checker - Your Verification Code",

  // ===== SMS Gateway (Generic) =====
  SMS_API_URL: process.env.SMS_API_URL || "",
  SMS_API_KEY: process.env.SMS_API_KEY || "",
  SMS_API_SECRET: process.env.SMS_API_SECRET || "",
  SMS_SENDER_ID: process.env.SMS_SENDER_ID || "",

  // ===== Server =====
  PORT: parseInt(process.env.PORT) || 3000,
  NODE_ENV: process.env.NODE_ENV || "development",
  CORS_ORIGIN: process.env.CORS_ORIGIN || "*",
};

// ============================================================
// MIDDLEWARE
// ============================================================

app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true }));
app.use(helmet());
app.use(cors({
  origin: CONFIG.CORS_ORIGIN,
  methods: ["GET", "POST", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization"],
}));

// Rate limiter for OTP endpoints: 5 requests per minute per IP
const otpLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  message: { 
    success: false, 
    error: "rate_limited",
    message: "Too many requests. Please wait before retrying." 
  },
  standardHeaders: true,
  legacyHeaders: false,
});

// ============================================================
// DATABASE POOL
// ============================================================

let pool = null;

async function getPool() {
  if (!pool) {
    pool = mysql.createPool({
      host: CONFIG.DB_HOST,
      port: CONFIG.DB_PORT,
      user: CONFIG.DB_USER,
      password: CONFIG.DB_PASSWORD,
      database: CONFIG.DB_NAME,
      waitForConnections: true,
      connectionLimit: 10,
      queueLimit: 0,
      enableKeepAlive: true,
      keepAliveInitialDelay: 0,
    });
  }
  return pool;
}

// ============================================================
// HELPER FUNCTIONS
// ============================================================

function generateOTP(length = 6) {
  const digits = "0123456789";
  let otp = "";
  for (let i = 0; i < length; i++) {
    otp += digits.charAt(Math.floor(Math.random() * digits.length));
  }
  return otp;
}

function normalizePhone(phone) {
  if (!phone) return null;
  let p = phone.toString().replace(/[\s\-+]/g, "");
  if (p.startsWith("880")) {
    p = "0" + p.slice(3);
  }
  if (/^(01[3-9])\d{8}$/.test(p)) {
    return p;
  }
  return null;
}

function normalizeEmail(email) {
  if (!email) return null;
  const e = email.toString().trim().toLowerCase();
  if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e)) {
    return e;
  }
  return null;
}

function normalizeContact(contact) {
  if (!contact) return null;
  const c = contact.toString().trim();
  const phone = normalizePhone(c);
  if (phone) return { type: "phone", value: phone };
  const email = normalizeEmail(c);
  if (email) return { type: "email", value: email };
  return null;
}

async function findUserByContact(pool, contact) {
  const normalized = normalizeContact(contact);
  if (!normalized) return null;
  
  // নতুন: user_contacts টেবিল থেকে খোঁজ (dual-login সাপোর্ট)
  const [rows] = await pool.query(
    `SELECT u.id, u.name, u.phone, u.email, u.created_at, u.profile_complete
     FROM users u
     JOIN user_contacts uc ON u.id = uc.user_id
     WHERE uc.value = ? AND uc.verified = 1
     LIMIT 1`,
    [normalized.value]
  );
  return rows[0] || null;
}

async function getRecentOtp(pool, contact) {
  const normalized = normalizeContact(contact);
  if (!normalized) return null;
  const cooldownMs = CONFIG.OTP_RESEND_COOLDOWN_SEC * 1000;
  const [rows] = await pool.query(
    `SELECT id, code, created_at FROM otps 
     WHERE contact = ? AND used_at IS NULL AND expires_at > NOW()
     ORDER BY id DESC LIMIT 1`,
    [normalized.value]
  );
  if (rows.length > 0) {
    const diff = Date.now() - new Date(rows[0].created_at).getTime();
    if (diff < cooldownMs) {
      return { otp: rows[0], remainingSec: Math.ceil((cooldownMs - diff) / 1000) };
    }
  }
  return null;
}

async function saveOtp(pool, contact, code) {
  const normalized = normalizeContact(contact);
  if (!normalized) throw new Error("Invalid contact");
  const expiresAt = new Date(Date.now() + CONFIG.OTP_EXPIRY_MINUTES * 60 * 1000);
  const [result] = await pool.query(
    `INSERT INTO otps (contact, code, expires_at) VALUES (?, ?, ?)`,
    [normalized.value, code, expiresAt]
  );
  return result.insertId;
}

async function markOtpUsed(pool, otpId) {
  await pool.query(`UPDATE otps SET used_at = NOW() WHERE id = ?`, [otpId]);
}

async function findValidOtp(pool, contact) {
  const normalized = normalizeContact(contact);
  if (!normalized) return null;
  const [rows] = await pool.query(
    `SELECT * FROM otps 
     WHERE contact = ? AND used_at IS NULL AND expires_at > NOW()
     ORDER BY id DESC LIMIT 1`,
    [normalized.value]
  );
  return rows[0] || null;
}

// ============================================================
// EMAIL & SMS
// ============================================================

async function sendOtpViaEmail(email, code) {
  if (!CONFIG.GMAIL_USER || !CONFIG.GMAIL_PASS) {
    const err = new Error("Email service not configured");
    err.statusCode = 503;
    err.code = "EMAIL_NOT_CONFIGURED";
    throw err;
  }
  const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: { user: CONFIG.GMAIL_USER, pass: CONFIG.GMAIL_PASS },
  });
  const mailOptions = {
    from: `"Payment Checker" <${CONFIG.GMAIL_FROM || CONFIG.GMAIL_USER}>`,
    to: email,
    subject: CONFIG.GMAIL_OTP_SUBJECT,
    text: `Your verification code is: ${code}\n\nValid for ${CONFIG.OTP_EXPIRY_MINUTES} minutes.`,
    html: `<h2>Payment Checker</h2><p>Your code: <b>${code}</b></p><p>Expires in ${CONFIG.OTP_EXPIRY_MINUTES} minutes.</p>`,
  };
  return await transporter.sendMail(mailOptions);
}

async function sendOtpViaSms(phone, code) {
  if (!CONFIG.SMS_API_URL) {
    const err = new Error("SMS service not configured");
    err.statusCode = 503;
    err.code = "SMS_NOT_CONFIGURED";
    throw err;
  }
  const message = `Payment Checker: ${code} is your code. Valid ${CONFIG.OTP_EXPIRY_MINUTES} min.`;
  const payload = {
    api_key: CONFIG.SMS_API_KEY,
    api_secret: CONFIG.SMS_API_SECRET,
    sender_id: CONFIG.SMS_SENDER_ID,
    recipient: phone,
    message: message,
  };
  try {
    const response = await axios.post(CONFIG.SMS_API_URL, payload, {
      headers: { "Content-Type": "application/json", "Accept": "application/json" },
      timeout: 10000,
    });
    const data = response.data;
    const success = data?.status === "success" || data?.success === true || 
                   (response.status >= 200 && response.status < 300);
    if (!success) throw new Error(data?.message || "SMS failed");
    return data;
  } catch (error) {
    if (error.response) {
      throw new Error(`SMS API error ${error.response.status}`);
    }
    throw error;
  }
}

async function sendOtp(contact, code) {
  const normalized = normalizeContact(contact);
  if (!normalized) {
    const err = new Error("Invalid contact format");
    err.statusCode = 400;
    throw err;
  }
  if (normalized.type === "phone") {
    return await sendOtpViaSms(normalized.value, code);
  } else {
    return await sendOtpViaEmail(normalized.value, code);
  }
}

function createToken(user) {
  return jwt.sign(
    { id: user.id, name: user.name, phone: user.phone, email: user.email },
    CONFIG.JWT_SECRET,
    { expiresIn: CONFIG.JWT_EXPIRES_IN }
  );
}

// ============================================================
// DATABASE INITIALIZATION
// ============================================================

async function initDatabase() {
  const p = await getPool();
  await p.query(`
    CREATE TABLE IF NOT EXISTS users (
      id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(255) NOT NULL DEFAULT '',
      phone VARCHAR(20) UNIQUE,
      email VARCHAR(255) UNIQUE,
      password_hash VARCHAR(255) NOT NULL DEFAULT '',
      profile_complete TINYINT(1) NOT NULL DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_phone (phone),
      INDEX idx_email (email)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
  await p.query(`
    CREATE TABLE IF NOT EXISTS user_contacts (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      type ENUM('phone', 'email') NOT NULL,
      value VARCHAR(255) NOT NULL,
      verified TINYINT(1) NOT NULL DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE INDEX idx_value (value),
      INDEX idx_user_id (user_id),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
  await p.query(`
    CREATE TABLE IF NOT EXISTS otps (
      id INT AUTO_INCREMENT PRIMARY KEY,
      contact VARCHAR(255) NOT NULL,
      code VARCHAR(10) NOT NULL,
      expires_at DATETIME NOT NULL,
      used_at DATETIME DEFAULT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_contact (contact),
      INDEX idx_code_contact (code, contact),
      INDEX idx_expires (expires_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
  console.log("✓ Database tables ready");
}

// ============================================================
// ROUTES
// ============================================================

// Health check
app.get("/health", async (req, res) => {
  let dbOk = false;
  try {
    const p = await getPool();
    await p.query("SELECT 1");
    dbOk = true;
  } catch (e) { dbOk = false; }
  res.json({
    ok: true,
    service: "Payment Checker OTP API",
    version: "1.0.0",
    database: dbOk ? "connected" : "disconnected",
    timestamp: new Date().toISOString(),
  });
});

// Root
app.get("/", (req, res) => {
  res.json({
    ok: true,
    service: "Payment Checker OTP API",
    endpoints: ["/health", "/api/check-contact", "/api/send-otp", "/api/send-otp-new", "/api/verify-otp"],
  });
});

// --------------------------------------------------------
// POST /api/check-contact
// Check if contact exists in database
// --------------------------------------------------------
app.post("/api/check-contact", otpLimiter, async (req, res) => {
  try {
    const { contact } = req.body;
    if (!contact) {
      return res.status(400).json({
        success: false,
        error: "INVALID_INPUT",
        message: "Contact is required",
      });
    }

    const normalized = normalizeContact(contact);
    if (!normalized) {
      return res.status(400).json({
        success: false,
        error: "INVALID_FORMAT",
        message: "Invalid phone or email format",
      });
    }

    const pool = await getPool();
    const user = await findUserByContact(pool, contact);

    if (user) {
      res.json({
        success: true,
        exists: true,
        isNewUser: false,
        message: "Account found",
      });
    } else {
      res.json({
        success: true,
        exists: false,
        isNewUser: true,
        message: "No account found with this contact",
      });
    }
  } catch (error) {
    console.error("Error in check-contact:", error);
    res.status(500).json({
      success: false,
      error: "SERVER_ERROR",
      message: error```javascript
/**
 * Payment Checker OTP System
 * Complete rewrite - .env only configuration
 * 
 * Endpoints:
 * - POST /api/check-contact  : Check if contact exists
 * - POST /api/send-otp      : For EXISTING users only
 * - POST /api/send-otp-new  : For NEW users (creates user + sends OTP)
 * - POST /api/verify-otp    : Verify OTP and get JWT token
 */

require("dotenv").config();
const express = require("express");
const mysql = require("mysql2/promise");
const nodemailer = require("nodemailer");
const axios = require("axios");
const jwt = require("jsonwebtoken");
const rateLimit = require("express-rate-limit");
const helmet = require("helmet");
const cors = require("cors");

const app = express();

// ============================================================
// CONFIGURATION (ALL from .env)
// ============================================================

const CONFIG = {
  // ===== Database =====
  DB_HOST: process.env.DB_HOST || "localhost",
  DB_PORT: parseInt(process.env.DB_PORT) || 3306,
  DB_USER: process.env.DB_USER || "root",
  DB_PASSWORD: process.env.DB_PASSWORD || "",
  DB_NAME: process.env.DB_NAME || "payment_checker",

  // ===== JWT =====
  JWT_SECRET: process.env.JWT_SECRET || "change-this-secret-in-production",
  JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN || "7d",

  // ===== OTP Settings =====
  OTP_LENGTH: parseInt(process.env.OTP_LENGTH) || 6,
  OTP_EXPIRY_MINUTES: parseInt(process.env.OTP_EXPIRY_MINUTES) || 5,
  OTP_RESEND_COOLDOWN_SEC: parseInt(process.env.OTP_RESEND_COOLDOWN_SEC) || 60,

  // ===== Gmail/Nodemailer =====
  GMAIL_USER: process.env.GMAIL_USER || "",
  GMAIL_PASS: process.env.GMAIL_PASS || "",
  GMAIL_FROM: process.env.GMAIL_FROM || "",
  GMAIL_OTP_SUBJECT: process.env.GMAIL_OTP_SUBJECT || "Payment Checker - Your Verification Code",

  // ===== SMS Gateway (Generic) =====
  SMS_API_URL: process.env.SMS_API_URL || "",
  SMS_API_KEY: process.env.SMS_API_KEY || "",
  SMS_API_SECRET: process.env.SMS_API_SECRET || "",
  SMS_SENDER_ID: process.env.SMS_SENDER_ID || "",

  // ===== Server =====
  PORT: parseInt(process.env.PORT) || 3000,
  NODE_ENV: process.env.NODE_ENV || "development",
  CORS_ORIGIN: process.env.CORS_ORIGIN || "*",
};

// ============================================================
// MIDDLEWARE
// ============================================================

app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true }));
app.use(helmet());
app.use(cors({
  origin: CONFIG.CORS_ORIGIN,
  methods: ["GET", "POST", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization"],
}));

// Rate limiter for OTP endpoints: 5 requests per minute per IP
const otpLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  message: { 
    success: false, 
    error: "rate_limited",
    message: "Too many requests. Please wait before retrying." 
  },
  standardHeaders: true,
  legacyHeaders: false,
});

// ============================================================
// DATABASE POOL
// ============================================================

let pool = null;

async function getPool() {
  if (!pool) {
    pool = mysql.createPool({
      host: CONFIG.DB_HOST,
      port: CONFIG.DB_PORT,
      user: CONFIG.DB_USER,
      password: CONFIG.DB_PASSWORD,
      database: CONFIG.DB_NAME,
      waitForConnections: true,
      connectionLimit: 10,
      queueLimit: 0,
      enableKeepAlive: true,
      keepAliveInitialDelay: 0,
    });
  }
  return pool;
}

// ============================================================
// HELPER FUNCTIONS
// ============================================================

function generateOTP(length = 6) {
  const digits = "0123456789";
  let otp = "";
  for (let i = 0; i < length; i++) {
    otp += digits.charAt(Math.floor(Math.random() * digits.length));
  }
  return otp;
}

function normalizePhone(phone) {
  if (!phone) return null;
  let p = phone.toString().replace(/[\s\-+]/g, "");
  if (p.startsWith("880")) {
    p = "0" + p.slice(3);
  }
  if (/^(01[3-9])\d{8}$/.test(p)) {
    return p;
  }
  return null;
}

function normalizeEmail(email) {
  if (!email) return null;
  const e = email.toString().trim().toLowerCase();
  if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e)) {
    return e;
  }
  return null;
}

function normalizeContact(contact) {
  if (!contact) return null;
  const c = contact.toString().trim();
  const phone = normalizePhone(c);
  if (phone) return { type: "phone", value: phone };
  const email = normalizeEmail(c);
  if (email) return { type: "email", value: email };
  return null;
}

async function findUserByContact(pool, contact) {
  const normalized = normalizeContact(contact);
  if (!normalized) return null;
  
  const [rows] = await pool.query(
    `SELECT u.id, u.name, u.phone, u.email, u.created_at, u.profile_complete
     FROM users u
     JOIN user_contacts uc ON u.id = uc.user_id
     WHERE uc.value = ? AND uc.verified = 1
     LIMIT 1`,
    [normalized.value]
  );
  return rows[0] || null;
}

async function getRecentOtp(pool, contact) {
  const normalized = normalizeContact(contact);
  if (!normalized) return null;
  const cooldownMs = CONFIG.OTP_RESEND_COOLDOWN_SEC * 1000;
  const [rows] = await pool.query(
    `SELECT id, code, created_at FROM otps 
     WHERE contact = ? AND used_at IS NULL AND expires_at > NOW()
     ORDER BY id DESC LIMIT 1`,
    [normalized.value]
  );
  if (rows.length > 0) {
    const diff = Date.now() - new Date(rows[0].created_at).getTime();
    if (diff < cooldownMs) {
      return { otp: rows[0], remainingSec: Math.ceil((cooldownMs - diff) / 1000) };
    }
  }
  return null;
}

async function saveOtp(pool, contact, code) {
  const normalized = normalizeContact(contact);
  if (!normalized) throw new Error("Invalid contact");
  const expiresAt = new Date(Date.now() + CONFIG.OTP_EXPIRY_MINUTES * 60 * 1000);
  const [result] = await pool.query(
    `INSERT INTO otps (contact, code, expires_at) VALUES (?, ?, ?)`,
    [normalized.value, code, expiresAt]
  );
  return result.insertId;
}

async function markOtpUsed(pool, otpId) {
  await pool.query(`UPDATE otps SET used_at = NOW() WHERE id = ?`, [otpId]);
}

async function findValidOtp(pool, contact) {
  const normalized = normalizeContact(contact);
  if (!normalized) return null;
  const [rows] = await pool.query(
    `SELECT * FROM otps 
     WHERE contact = ? AND used_at IS NULL AND expires_at > NOW()
     ORDER BY id DESC LIMIT 1`,
    [normalized.value]
  );
  return rows[0] || null;
}

// ============================================================
// EMAIL & SMS
// ============================================================

async function sendOtpViaEmail(email, code) {
  if (!CONFIG.GMAIL_USER || !CONFIG.GMAIL_PASS) {
    const err = new Error("Email service not configured");
    err.statusCode = 503;
    err.code = "EMAIL_NOT_CONFIGURED";
    throw err;
  }
  const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: { user: CONFIG.GMAIL_USER, pass: CONFIG.GMAIL_PASS },
  });
  const mailOptions = {
    from: `"Payment Checker" <${CONFIG.GMAIL_FROM || CONFIG.GMAIL_USER}>`,
    to: email,
    subject: CONFIG.GMAIL_OTP_SUBJECT,
    text: `Your verification code is: ${code}\n\nValid for ${CONFIG.OTP_EXPIRY_MINUTES} minutes.`,
    html: `<h2>Payment Checker</h2><p>Your code: <b>${code}</b></p><p>Expires in ${CONFIG.OTP_EXPIRY_MINUTES} minutes.</p>`,
  };
  return await transporter.sendMail(mailOptions);
}

async function sendOtpViaSms(phone, code) {
  if (!CONFIG.SMS_API_URL) {
    const err = new Error("SMS service not configured");
    err.statusCode = 503;
    err.code = "SMS_NOT_CONFIGURED";
    throw err;
  }
  const message = `Payment Checker: ${code} is your code. Valid ${CONFIG.OTP_EXPIRY_MINUTES} min.`;
  const payload = {
    api_key: CONFIG.SMS_API_KEY,
    api_secret: CONFIG.SMS_API_SECRET,
    sender_id: CONFIG.SMS_SENDER_ID,
    recipient: phone,
    message: message,
  };
  try {
    const response = await axios.post(CONFIG.SMS_API_URL, payload, {
      headers: { "Content-Type": "application/json", "Accept": "application/json" },
      timeout: 10000,
    });
    const data = response.data;
    const success = data?.status === "success" || data?.success === true || 
                   (response.status >= 200 && response.status < 300);
    if (!success) throw new Error(data?.message || "SMS failed");
    return data;
  } catch (error) {
    if (error.response) {
      throw new Error(`SMS API error ${error.response.status}`);
    }
    throw error;
  }
}

async function sendOtp(contact, code) {
  const normalized = normalizeContact(contact);
  if (!normalized) {
    const err = new Error("Invalid contact format");
    err.statusCode = 400;
    throw err;
  }
  if (normalized.type === "phone") {
    return await sendOtpViaSms(normalized.value, code);
  } else {
    return await sendOtpViaEmail(normalized.value, code);
  }
}

function createToken(user) {
  return jwt.sign(
    { id: user.id, name: user.name, phone: user.phone, email: user.email },
    CONFIG.JWT_SECRET,
    { expiresIn: CONFIG.JWT_EXPIRES_IN }
  );
}

// ============================================================
// DATABASE INITIALIZATION
// ============================================================

async function initDatabase() {
  const p = await getPool();
  await p.query(`
    CREATE TABLE IF NOT EXISTS users (
      id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(255) NOT NULL DEFAULT '',
      phone VARCHAR(20) UNIQUE,
      email VARCHAR(255) UNIQUE,
      password_hash VARCHAR(255) NOT NULL DEFAULT '',
      profile_complete TINYINT(1) NOT NULL DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_phone (phone),
      INDEX idx_email (email)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
  await p.query(`
    CREATE TABLE IF NOT EXISTS user_contacts (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      type ENUM('phone', 'email') NOT NULL,
      value VARCHAR(255) NOT NULL,
      verified TINYINT(1) NOT NULL DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE INDEX idx_value (value),
      INDEX idx_user_id (user_id),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
  await p.query(`
    CREATE TABLE IF NOT EXISTS otps (
      id INT AUTO_INCREMENT PRIMARY KEY,
      contact VARCHAR(255) NOT NULL,
      code VARCHAR(10) NOT NULL,
      expires_at DATETIME NOT NULL,
      used_at DATETIME DEFAULT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_contact (contact),
      INDEX idx_code_contact (code, contact),
      INDEX idx_expires (expires_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
  console.log("✓ Database tables ready");
}

// ============================================================
// ROUTES
// ============================================================

// Health check
app.get("/health", async (req, res) => {
  let dbOk = false;
  try {
    const p = await getPool();
    await p.query("SELECT 1");
    dbOk = true;
  } catch (e) { dbOk = false; }
  res.json({
    ok: true,
    service: "Payment Checker OTP API",
    version: "1.0.0",
    database: dbOk ? "connected" : "disconnected",
    timestamp: new Date().toISOString(),
  });
});

// Root
app.get("/", (req, res) => {
  res.json({
    ok: true,
    service: "Payment Checker OTP API",
    endpoints: ["/health", "/api/check-contact", "/api/send-otp", "/api/send-otp-new", "/api/verify-otp"],
  });
});

// --------------------------------------------------------
// POST /api/check-contact
// Check if contact exists in database
// --------------------------------------------------------
app.post("/api/check-contact", otpLimiter, async (req, res) => {
  try {
    const { contact } = req.body;
    if (!contact) {
      return res.status(400).json({
        success: false,
        error: "INVALID_INPUT",
        message: "Contact is required",
      });
    }

    const normalized = normalizeContact(contact);
    if (!normalized) {
      return res.status(400).json({
        success: false,
        error: "INVALID_FORMAT",
        message: "Invalid phone or email format",
      });
    }

    const pool = await getPool();
    const user = await findUserByContact(pool, contact);

    if (user) {
      res.json({
        success: true,
        exists: true,
        isNewUser: false,
        message: "Account found",
      });
    } else {
      res.json({
        success: true,
        exists: false,
        isNewUser: true,
        message: "No account found with this contact",
      });
    }
  } catch (error) {
    console.error("Error in check-contact:", error);
    res.status(500).json({
      success: false,
      error: "SERVER_ERROR",
      message: error.message || "Internal server error",
    });
  }
});

// --------------------------------------------------------
// POST /api/send-otp
// For EXISTING users only - returns user_not_found if not exists
// --------------------------------------------------------
app.post("/api/send-otp", otpLimiter, async (req, res) => {
  try {
    const { contact } = req.body;
    if (!contact) {
      return res.status(400).json({
        success: false,
        error: "INVALID_INPUT",
        message: "Contact is required",
      });
    }

    const pool = await getPool();
    
    // Check if user exists
    const user = await findUserByContact(pool, contact);
    if (!user) {
      return res.status(404).json({
        success: false,
        error: