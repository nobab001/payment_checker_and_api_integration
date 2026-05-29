"use strict";

const {
  MAX_PER_TYPE,
  normalizeContact,
  isBdPhone,
  isGmail,
  credentialType,
  findUserByCredential,
  ensureCredential,
  countCredentials,
} = require("../services/credentialAuth");

/**
 * @param {import('express').Express} app
 * @param {import('mysql2/promise').Pool} pool
 * @param {object} deps
 */
function registerCredentialRoutes(app, pool, deps) {
  const {
    authMiddleware,
    generateOtp,
    dispatchSmsFromSettings,
    sendOtpToGmail,
    OTP_EXPIRY_MIN,
    RESEND_COOLDOWN_SEC,
    userRowToJson,
  } = deps;

  async function listContactsForUser(userId) {
    const seen = new Set();
    const phones = [];
    const emails = [];

    const add = (type, raw) => {
      const v = normalizeContact(raw);
      if (!v || seen.has(v)) return;
      if (type === "phone" && !isBdPhone(v)) return;
      if (type === "email" && !isGmail(v)) return;
      seen.add(v);
      if (type === "phone") phones.push(v);
      else emails.push(v);
    };

    const [creds] = await pool.query(
      `SELECT type, value FROM user_credentials WHERE user_id = ? ORDER BY id`,
      [userId]
    );
    for (const row of creds) add(row.type, row.value);

    const [u] = await pool.query(
      `SELECT phone, email FROM users WHERE id = ? LIMIT 1`,
      [userId]
    );
    if (u.length) {
      if (u[0].phone) add("phone", u[0].phone);
      if (u[0].email) add("email", u[0].email);
    }

    if (!phones.length && !emails.length) {
      await pool.query(
        `INSERT IGNORE INTO user_credentials (user_id, type, value, verified_at)
         SELECT id, 'phone', phone, COALESCE(updated_at, created_at)
         FROM users WHERE id = ? AND phone IS NOT NULL AND phone <> ''`,
        [userId]
      );
      await pool.query(
        `INSERT IGNORE INTO user_credentials (user_id, type, value, verified_at)
         SELECT id, 'email', email, COALESCE(updated_at, created_at)
         FROM users WHERE id = ? AND email IS NOT NULL AND email <> ''`,
        [userId]
      );
      const [again] = await pool.query(
        `SELECT type, value FROM user_credentials WHERE user_id = ? ORDER BY id`,
        [userId]
      );
      for (const row of again) add(row.type, row.value);
    }

    return { phones, emails, maxPerType: MAX_PER_TYPE };
  }

  async function issueLinkOtp(conn, contact) {
    const value = normalizeContact(contact);
    if (!isBdPhone(value) && !isGmail(value)) {
      const err = new Error("Enter a valid Bangladesh mobile or Gmail");
      err.statusCode = 400;
      throw err;
    }

    const [last] = await conn.query(
      `SELECT created_at FROM otps WHERE contact = ? ORDER BY id DESC LIMIT 1`,
      [value]
    );
    if (last.length) {
      const prev = new Date(last[0].created_at).getTime();
      if (Date.now() - prev < RESEND_COOLDOWN_SEC * 1000) {
        const err = new Error(`Please wait ${RESEND_COOLDOWN_SEC} seconds before resending`);
        err.statusCode = 429;
        throw err;
      }
    }

    const code = generateOtp();
    const expires = new Date(Date.now() + OTP_EXPIRY_MIN * 60_000);
    const [ins] = await conn.query(
      `INSERT INTO otps (contact, code, expires_at) VALUES (?, ?, ?)`,
      [value, code, expires]
    );

    try {
      if (isBdPhone(value)) {
        const text = `আপনার Payment Checker যোগাযোগ যাচাই OTP: ${code}। কাউকে বলবেন না।`;
        await dispatchSmsFromSettings(value, text);
      } else {
        await sendOtpToGmail(value, code);
      }
    } catch (sendErr) {
      await conn.query(`DELETE FROM otps WHERE id = ?`, [ins.insertId]);
      throw sendErr;
    }
    return value;
  }

  async function verifyOtpCode(conn, contact, code) {
    const value = normalizeContact(contact);
    const otpCode = String(code || "").trim();
    if (!value || !otpCode) {
      const err = new Error("contact and code required");
      err.statusCode = 400;
      throw err;
    }

    const [otpRows] = await conn.query(
      `SELECT * FROM otps
       WHERE contact = ? AND used_at IS NULL
       ORDER BY id DESC
       LIMIT 1`,
      [value]
    );
    if (!otpRows.length) {
      const err = new Error("No active OTP");
      err.statusCode = 400;
      throw err;
    }
    const otpRow = otpRows[0];
    if (String(otpRow.code) !== otpCode) {
      const err = new Error("Invalid code");
      err.statusCode = 400;
      throw err;
    }
    if (new Date(otpRow.expires_at) < new Date()) {
      const err = new Error("OTP expired");
      err.statusCode = 410;
      throw err;
    }
    await conn.query("UPDATE otps SET used_at = NOW() WHERE id = ?", [otpRow.id]);
    return value;
  }

  app.get("/api/credentials", authMiddleware, async (req, res) => {
    try {
      const data = await listContactsForUser(req.userId);
      return res.json({ success: true, ...data });
    } catch (e) {
      console.error("[credentials/list]", e);
      return res.status(500).json({ success: false, message: "Server error" });
    }
  });

  app.post("/api/credentials/send-otp", authMiddleware, async (req, res) => {
    const contact = normalizeContact(req.body?.contact || req.body?.phone);
    if (!contact) {
      return res.status(400).json({ success: false, message: "contact required" });
    }
    const type = credentialType(contact);
    if (!type) {
      return res.status(400).json({
        success: false,
        message: "Enter a valid Bangladesh mobile or Gmail",
      });
    }

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      const owner = await findUserByCredential(conn, contact);
      if (owner && Number(owner.id) !== Number(req.userId)) {
        await conn.rollback();
        return res.status(409).json({
          success: false,
          message: "This number or email is already linked to another account",
        });
      }

      const [onSelf] = await conn.query(
        `SELECT 1 FROM user_credentials WHERE user_id = ? AND value = ? LIMIT 1`,
        [req.userId, contact]
      );
      if (onSelf.length) {
        await conn.rollback();
        return res.status(409).json({
          success: false,
          message: "Already linked to your account",
        });
      }

      const cnt = await countCredentials(conn, req.userId, type);
      if (cnt >= MAX_PER_TYPE) {
        await conn.rollback();
        return res.status(400).json({
          success: false,
          message: `Maximum ${MAX_PER_TYPE} ${type === "phone" ? "phone numbers" : "Gmail addresses"} per account`,
        });
      }

      await issueLinkOtp(conn, contact);
      await conn.commit();
      return res.json({ success: true, message: "OTP sent" });
    } catch (e) {
      try {
        await conn.rollback();
      } catch (_) {}
      const status = e.statusCode || 500;
      return res.status(status).json({
        success: false,
        message: e.message || "Server error",
      });
    } finally {
      conn.release();
    }
  });

  app.post("/api/credentials/verify", authMiddleware, async (req, res) => {
    const contact = normalizeContact(req.body?.contact || req.body?.phone);
    const code = String(req.body?.code || "").trim();
    if (!contact || !code) {
      return res.status(400).json({ success: false, message: "contact and code required" });
    }

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      const owner = await findUserByCredential(conn, contact);
      if (owner && Number(owner.id) !== Number(req.userId)) {
        await conn.rollback();
        return res.status(409).json({
          success: false,
          message: "This number or email is already linked to another account",
        });
      }

      const type = credentialType(contact);
      if (!type) {
        await conn.rollback();
        return res.status(400).json({
          success: false,
          message: "Enter a valid Bangladesh mobile or Gmail",
        });
      }

      const [onSelf] = await conn.query(
        `SELECT 1 FROM user_credentials WHERE user_id = ? AND value = ? LIMIT 1`,
        [req.userId, contact]
      );
      if (onSelf.length) {
        await conn.rollback();
        return res.status(409).json({
          success: false,
          message: "Already linked to your account",
        });
      }

      const cnt = await countCredentials(conn, req.userId, type);
      if (cnt >= MAX_PER_TYPE) {
        await conn.rollback();
        return res.status(400).json({
          success: false,
          message: `Maximum ${MAX_PER_TYPE} credentials of this type`,
        });
      }

      await verifyOtpCode(conn, contact, code);
      await ensureCredential(conn, req.userId, contact, new Date());
      await conn.commit();

      const listed = await listContactsForUser(req.userId);
      const [rows] = await pool.query("SELECT * FROM users WHERE id = ?", [req.userId]);
      return res.json({
        success: true,
        message: "Credential linked",
        ...listed,
        user: userRowToJson(rows[0]),
      });
    } catch (e) {
      try {
        await conn.rollback();
      } catch (_) {}
      const status = e.statusCode || 500;
      return res.status(status).json({
        success: false,
        message: e.message || "Server error",
      });
    } finally {
      conn.release();
    }
  });
}

module.exports = { registerCredentialRoutes };
