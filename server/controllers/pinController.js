"use strict";

const {
  normalizeContact,
  isBdPhone,
  isGmail,
  ensureCredential,
} = require("../services/credentialAuth");
const { assertPinSavedCorrectly, isPinHashStorageValid } = require("../utils/pinAuth");

/**
 * @param {import('mysql2/promise').Pool} pool
 * @param {object} deps - OTP + PIN helpers from app.js
 */
function registerPinRoutes(app, pool, deps) {
  const {
    authMiddleware,
    generateOtp,
    dispatchSmsFromSettings,
    sendOtpToGmail,
    OTP_EXPIRY_MIN,
    RESEND_COOLDOWN_SEC,
    hashPin,
    verifyUserPin,
    isValidPinFormat,
  } = deps;

  async function contactBelongsToUser(conn, userId, contact) {
    const value = normalizeContact(contact);
    const [creds] = await conn.query(
      `SELECT 1 FROM user_credentials WHERE user_id = ? AND value = ? LIMIT 1`,
      [userId, value]
    );
    if (creds.length) return value;
    const [users] = await conn.query(
      `SELECT 1 FROM users WHERE id = ? AND (phone = ? OR LOWER(email) = ?) LIMIT 1`,
      [userId, value, value]
    );
    return users.length ? value : null;
  }

  /** Legacy accounts with no stored contacts may recover using any valid login contact. */
  async function resolveContactForPinRecovery(conn, userId, contact) {
    const owned = await contactBelongsToUser(conn, userId, contact);
    if (owned) return owned;
    const list = await listContactsForUser(userId);
    if (list.length > 0) return null;
    const v = normalizeContact(contact);
    if (!isBdPhone(v) && !isGmail(v)) return null;
    return v;
  }

  async function listContactsForUser(userId) {
    const seen = new Set();
    const out = [];
    const add = (type, raw) => {
      const v = normalizeContact(raw);
      if (!v || seen.has(v)) return;
      if (type === "phone" && !isBdPhone(v)) return;
      if (type === "email" && !isGmail(v)) return;
      seen.add(v);
      out.push({ type, value: v });
    };

    const [creds] = await pool.query(
      `SELECT type, value FROM user_credentials WHERE user_id = ? ORDER BY type, id`,
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

    if (!out.length) {
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
        `SELECT type, value FROM user_credentials WHERE user_id = ?`,
        [userId]
      );
      for (const row of again) add(row.type, row.value);
    }

    return out;
  }

  async function issueOtp(conn, contact) {
    const phone = normalizeContact(contact);
    if (!isBdPhone(phone) && !isGmail(phone)) {
      const err = new Error("Enter a valid Bangladesh mobile or Gmail");
      err.statusCode = 400;
      throw err;
    }

    const [last] = await conn.query(
      `SELECT created_at FROM otps WHERE contact = ? ORDER BY id DESC LIMIT 1`,
      [phone]
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
      [phone, code, expires]
    );

    try {
      if (isBdPhone(phone)) {
        const text = `আপনার Payment Checker PIN রিসেট OTP: ${code}। কাউকে বলবেন না।`;
        await dispatchSmsFromSettings(phone, text);
      } else {
        await sendOtpToGmail(phone, code);
      }
    } catch (sendErr) {
      const allowConsole = String(process.env.ALLOW_OTP_WITHOUT_SMS || "").trim() === "1";
      if (allowConsole) {
        console.log(
          `\n🔑 [ALLOW_OTP_WITHOUT_SMS] PIN OTP for ${phone}: ${code}  (expires in ${OTP_EXPIRY_MIN} min)\n`
        );
      } else {
        await conn.query(`DELETE FROM otps WHERE id = ?`, [ins.insertId]);
        throw sendErr;
      }
    }
    return phone;
  }

  /** Contacts linked to this account (for forgot-PIN picker). */
  app.get("/api/auth/pin-contacts", authMiddleware, async (req, res) => {
    try {
      const contacts = await listContactsForUser(req.userId);
      return res.json({ success: true, contacts });
    } catch (e) {
      console.error("[pin-contacts]", e);
      return res.status(500).json({ success: false, message: "Server error", contacts: [] });
    }
  });

  /** Change PIN when current PIN is known (any device, logged in). */
  app.post("/api/auth/change-pin", authMiddleware, async (req, res) => {
    const currentPin = String(req.body?.currentPin || req.body?.current_pin || "").trim();
    const newPin = String(req.body?.newPin || req.body?.new_pin || "").trim();

    if (!isValidPinFormat(newPin)) {
      return res.status(400).json({ success: false, message: "New PIN must be 4 to 6 digits" });
    }
    if (currentPin === newPin) {
      return res.status(400).json({ success: false, message: "New PIN must be different" });
    }

    try {
      const [rows] = await pool.query("SELECT * FROM users WHERE id = ? LIMIT 1", [req.userId]);
      if (!rows.length) {
        return res.status(404).json({ success: false, message: "User not found" });
      }
      const user = rows[0];
      const hasPin = user.pin != null && String(user.pin).length > 0;
      if (hasPin) {
        if (!isValidPinFormat(currentPin)) {
          return res.status(400).json({ success: false, message: "Current PIN must be 4 to 6 digits" });
        }
        if (!verifyUserPin(user, currentPin)) {
          return res.status(403).json({ success: false, message: "Current PIN is incorrect" });
        }
      }

      const pinStored = hashPin(newPin);
      await pool.query(`UPDATE users SET pin = ?, updated_at = NOW() WHERE id = ?`, [
        pinStored,
        req.userId,
      ]);
      const [pinCheck] = await pool.query("SELECT pin FROM users WHERE id = ? LIMIT 1", [
        req.userId,
      ]);
      try {
        assertPinSavedCorrectly(pinCheck[0], newPin);
      } catch (saveErr) {
        console.error("[change-pin]", saveErr.message);
        return res.status(500).json({
          success: false,
          code: "PIN_STORAGE_CORRUPT",
          message:
            "PIN could not be stored correctly. Ask admin to run: ALTER TABLE users MODIFY pin VARCHAR(255); then reset PIN again.",
        });
      }
      const [fresh] = await pool.query("SELECT * FROM users WHERE id = ? LIMIT 1", [req.userId]);
      return res.json({
        success: true,
        message: "PIN updated",
        pinConfigured: true,
        user: deps.userRowToJson(fresh[0]),
      });
    } catch (e) {
      console.error("[change-pin]", e);
      return res.status(500).json({ success: false, message: "Server error" });
    }
  });

  /** Send OTP to a phone/email that belongs to the logged-in user. */
  app.post("/api/auth/forgot-pin/send-otp", authMiddleware, async (req, res) => {
    const contact = normalizeContact(req.body?.contact || req.body?.phone);
    if (!contact) {
      return res.status(400).json({ success: false, message: "contact required" });
    }

    const conn = await pool.getConnection();
    try {
      const owned = await resolveContactForPinRecovery(conn, req.userId, contact);
      if (!owned) {
        return res.status(403).json({
          success: false,
          message:
            "This number or email is not linked to your account. Use the same contact you log in with.",
        });
      }
      await issueOtp(conn, owned);
      return res.json({ success: true, message: "OTP sent", contact: owned });
    } catch (e) {
      const status = e.statusCode || 500;
      let msg = e.message || "Request failed";
      if (status === 503) {
        msg = msg.includes("Gmail") ? msg : "SMS gateway not configured";
      } else if (status >= 500) {
        msg = "Server error";
      }
      return res.status(status >= 400 && status < 600 ? status : 500).json({
        success: false,
        message: msg,
      });
    } finally {
      conn.release();
    }
  });

  /** Verify OTP and set a new PIN (forgot PIN flow). */
  app.post("/api/auth/forgot-pin/reset", authMiddleware, async (req, res) => {
    const contact = normalizeContact(req.body?.contact || req.body?.phone);
    const code = normalizeContact(req.body?.code);
    const newPin = String(req.body?.newPin || req.body?.new_pin || "").trim();

    if (!contact || !code) {
      return res.status(400).json({ success: false, message: "contact and code required" });
    }
    if (!isValidPinFormat(newPin)) {
      return res.status(400).json({ success: false, message: "New PIN must be 4 to 6 digits" });
    }

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      const owned = await resolveContactForPinRecovery(conn, req.userId, contact);
      if (!owned) {
        await conn.rollback();
        return res.status(403).json({
          success: false,
          message:
            "This number or email is not linked to your account. Use the same contact you log in with.",
        });
      }

      const [otpRows] = await conn.query(
        `SELECT * FROM otps WHERE contact = ? AND used_at IS NULL ORDER BY id DESC LIMIT 1`,
        [owned]
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

      const pinStored = hashPin(newPin);
      await conn.query(`UPDATE users SET pin = ?, updated_at = NOW() WHERE id = ?`, [
        pinStored,
        req.userId,
      ]);
      const [pinCheck] = await conn.query("SELECT pin FROM users WHERE id = ? LIMIT 1", [
        req.userId,
      ]);
      try {
        assertPinSavedCorrectly(pinCheck[0], newPin);
      } catch (saveErr) {
        await conn.rollback();
        console.error("[forgot-pin/reset]", saveErr.message);
        return res.status(500).json({
          success: false,
          code: "PIN_STORAGE_CORRUPT",
          message:
            "PIN could not be stored correctly. Run DB migration (users.pin VARCHAR(255)) then reset PIN again.",
        });
      }
      await ensureCredential(conn, req.userId, owned, new Date());
      if (isBdPhone(owned)) {
        await conn.query(
          `UPDATE users SET phone = ? WHERE id = ? AND (phone IS NULL OR phone = '')`,
          [owned, req.userId]
        );
      } else if (isGmail(owned)) {
        await conn.query(
          `UPDATE users SET email = ? WHERE id = ? AND (email IS NULL OR email = '')`,
          [owned, req.userId]
        );
      }
      await conn.query("UPDATE otps SET used_at = NOW() WHERE id = ?", [otpRow.id]);
      await conn.commit();

      const [fresh] = await pool.query("SELECT * FROM users WHERE id = ? LIMIT 1", [req.userId]);
      return res.json({
        success: true,
        message: "PIN reset successful",
        pinConfigured: true,
        devicePinVerified: true,
        user: deps.userRowToJson(fresh[0]),
      });
    } catch (e) {
      try {
        await conn.rollback();
      } catch (_) {}
      console.error("[forgot-pin/reset]", e);
      return res.status(500).json({ success: false, message: "Server error" });
    } finally {
      conn.release();
    }
  });
}

module.exports = { registerPinRoutes };
