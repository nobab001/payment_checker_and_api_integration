"use strict";

/**
 * Login / signup policy (multi-credential + device lock)
 *
 * Flow (verify-otp after OTP is valid):
 * 1. Resolve credential in user_credentials → user_id (or treat as signup).
 * 2. If device_id present: load user_devices row FOR UPDATE.
 *    - Known device + different account → reject (403 DEVICE_BOUND).
 *    - Known device + same account → allow, refresh last_login.
 *    - Unknown device → allow; bind after user is known.
 * 3. Signup: create users row + primary credential (verified_at = now).
 * 4. Legacy users without credential rows get backfilled on login.
 */

const MAX_PER_TYPE = 5;

function isBdPhone(s) {
  return /^(013|014|015|016|017|018|019)\d{8}$/.test(String(s || "").trim());
}

function isGmail(s) {
  return /^[^\s@]+@gmail\.com$/i.test(String(s || "").trim());
}

function normalizeContact(raw) {
  const s = String(raw || "").trim();
  if (s.includes("@")) return s.toLowerCase();
  return s;
}

function credentialType(contact) {
  const c = normalizeContact(contact);
  if (isBdPhone(c)) return "phone";
  if (isGmail(c)) return "email";
  return null;
}

function isUserBlocked(user) {
  if (!user) return false;
  if (user.status === "blocked") return true;
  return user.blocked === 1 || user.blocked === true;
}

/**
 * @returns {Promise<object|null>}
 */
async function findUserByCredential(conn, contact) {
  const value = normalizeContact(contact);
  const [viaCred] = await conn.query(
    `SELECT u.* FROM user_credentials c
     INNER JOIN users u ON u.id = c.user_id
     WHERE c.value = ?
     LIMIT 1`,
    [value]
  );
  if (viaCred.length) return viaCred[0];

  const [legacy] = await conn.query(
    "SELECT * FROM users WHERE phone = ? OR email = ? LIMIT 1",
    [value, value]
  );
  return legacy[0] || null;
}

async function countCredentials(conn, userId, type) {
  const [[row]] = await conn.query(
    `SELECT COUNT(*) AS cnt FROM user_credentials WHERE user_id = ? AND type = ?`,
    [userId, type]
  );
  return Number(row.cnt) || 0;
}

/**
 * Link a verified phone/email to an account (signup + profile + future link API).
 */
async function ensureCredential(conn, userId, contact, verifiedAt) {
  const value = normalizeContact(contact);
  const type = credentialType(value);
  if (!type) {
    const err = new Error("Unsupported contact type");
    err.statusCode = 400;
    throw err;
  }

  const [existing] = await conn.query(
    `SELECT id, user_id FROM user_credentials WHERE value = ? LIMIT 1`,
    [value]
  );
  if (existing.length && Number(existing[0].user_id) !== Number(userId)) {
    const err = new Error("Credential already linked to another account");
    err.statusCode = 409;
    throw err;
  }

  if (!existing.length) {
    const cnt = await countCredentials(conn, userId, type);
    if (cnt >= MAX_PER_TYPE) {
      const err = new Error(`Maximum ${MAX_PER_TYPE} ${type} credentials per account`);
      err.statusCode = 400;
      throw err;
    }
    await conn.query(
      `INSERT INTO user_credentials (user_id, type, value, verified_at) VALUES (?, ?, ?, ?)`,
      [userId, type, value, verifiedAt || new Date()]
    );
  } else if (verifiedAt) {
    await conn.query(
      `UPDATE user_credentials SET verified_at = COALESCE(verified_at, ?) WHERE value = ?`,
      [verifiedAt, value]
    );
  }

  if (type === "phone") {
    await conn.query(`UPDATE users SET phone = ? WHERE id = ? AND (phone IS NULL OR phone = '')`, [
      value,
      userId,
    ]);
  } else {
    await conn.query(`UPDATE users SET email = ? WHERE id = ? AND (email IS NULL OR email = '')`, [
      value,
      userId,
    ]);
  }
}

/**
 * Device binding check. Call inside a transaction before creating a new user.
 *
 * @param {number|null} requestedUserId - null when signing up a brand-new account
 */
async function evaluateDeviceBinding(conn, deviceId, requestedUserId) {
  const id = String(deviceId || "").trim();
  if (!id) {
    return { allowed: true, skip: true };
  }

  const [rows] = await conn.query(
    `SELECT user_id FROM user_devices WHERE device_id = ? LIMIT 1 FOR UPDATE`,
    [id]
  );

  if (!rows.length) {
    return { allowed: true, isNewDevice: true };
  }

  const ownerId = Number(rows[0].user_id);
  if (requestedUserId == null) {
    return {
      allowed: false,
      code: "DEVICE_BOUND",
      message:
        "This device is already registered to another account. Sign up is not allowed on this device.",
      boundUserId: ownerId,
    };
  }

  if (ownerId !== Number(requestedUserId)) {
    return {
      allowed: false,
      code: "DEVICE_BOUND",
      message:
        "This device belongs to another account. You can only log in with the account that first used this device.",
      boundUserId: ownerId,
    };
  }

  return { allowed: true, isKnownDevice: true, ownerUserId: ownerId };
}

/**
 * Phone + Gmail strings for the account that owns this device.
 */
async function getBoundAccountContacts(conn, userId) {
  const phones = [];
  const emails = [];
  const seen = new Set();

  const add = (type, value) => {
    const v = String(value || "").trim();
    if (!v || seen.has(`${type}:${v}`)) return;
    seen.add(`${type}:${v}`);
    if (type === "phone") phones.push(v);
    else emails.push(v);
  };

  const [creds] = await conn.query(
    `SELECT type, value FROM user_credentials WHERE user_id = ? ORDER BY type, value`,
    [userId]
  );
  for (const row of creds) {
    add(row.type, row.value);
  }

  const [users] = await conn.query(
    `SELECT phone, email FROM users WHERE id = ? LIMIT 1`,
    [userId]
  );
  if (users.length) {
    add("phone", users[0].phone);
    add("email", users[0].email);
  }

  return { phones, emails };
}

function formatBoundAccountLabel({ phones, emails }) {
  const parts = [...phones, ...emails].filter(Boolean);
  return parts.join(", ");
}

function buildDeviceBoundMessageBn(boundAccountLabel) {
  const label = String(boundAccountLabel || "").trim();
  const who = label ? `(${label}) ` : "";
  return (
    `আপনার এই ডিভাইসটি ${who}অ্যাকাউন্টের সাথে লিংক করা রয়েছে। ` +
    `অর্থাৎ আপনি নতুন কোনো অ্যাকাউন্ট করতে পারবেন না। ` +
    `আপনাকে আপনার আগের অ্যাকাউন্টটি ব্যবহার করতে হবে।`
  );
}

/**
 * Pre-OTP / pre-send-otp: can this contact log in or sign up on this device?
 */
async function evaluateDeviceLoginEligibility(conn, contact, deviceId) {
  const id = String(deviceId || "").trim();
  if (!id) {
    return { allowed: true };
  }

  const user = await findUserByCredential(conn, contact);
  const requestedUserId = user ? Number(user.id) : null;
  const deviceCheck = await evaluateDeviceBinding(conn, id, requestedUserId);

  if (deviceCheck.allowed) {
    return { allowed: true };
  }

  const contacts = await getBoundAccountContacts(conn, deviceCheck.boundUserId);
  const boundAccountLabel = formatBoundAccountLabel(contacts);

  return {
    allowed: false,
    code: deviceCheck.code || "DEVICE_BOUND",
    boundUserId: deviceCheck.boundUserId,
    boundAccountLabel,
    boundPhones: contacts.phones,
    boundEmails: contacts.emails,
    message: buildDeviceBoundMessageBn(boundAccountLabel),
  };
}

async function bindDeviceToUser(conn, userId, deviceId) {
  const id = String(deviceId || "").trim();
  if (!id) return;
  await conn.query(
    `INSERT INTO user_devices (user_id, device_id, last_login)
     VALUES (?, ?, NOW())
     ON DUPLICATE KEY UPDATE last_login = NOW()`,
    [userId, id]
  );
}

async function createUserWithPrimaryCredential(conn, contact) {
  const value = normalizeContact(contact);
  const type = credentialType(value);
  if (!type) {
    const err = new Error("Unsupported contact type");
    err.statusCode = 400;
    throw err;
  }

  const insPhone = type === "phone" ? value : null;
  const insEmail = type === "email" ? value : null;

  const [r] = await conn.query(
    `INSERT INTO users (phone, email, name, role, status) VALUES (?, ?, '', 'user', 'active')`,
    [insPhone, insEmail]
  );
  const userId = r.insertId;
  await conn.query(
    `INSERT INTO user_credentials (user_id, type, value, verified_at) VALUES (?, ?, ?, NOW())`,
    [userId, type, value]
  );
  const [inserted] = await conn.query("SELECT * FROM users WHERE id = ? LIMIT 1", [userId]);
  return inserted[0];
}

module.exports = {
  MAX_PER_TYPE,
  isBdPhone,
  isGmail,
  normalizeContact,
  credentialType,
  isUserBlocked,
  findUserByCredential,
  countCredentials,
  ensureCredential,
  evaluateDeviceBinding,
  getBoundAccountContacts,
  formatBoundAccountLabel,
  buildDeviceBoundMessageBn,
  evaluateDeviceLoginEligibility,
  bindDeviceToUser,
  createUserWithPrimaryCredential,
};
