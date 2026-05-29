"use strict";

const crypto = require("crypto");

const PBKDF2_ITERATIONS = 120000;
const PBKDF2_KEYLEN = 32;
const PBKDF2_DIGEST = "sha256";

function isValidPinFormat(pin) {
  const p = String(pin || "").trim();
  return /^\d{4,6}$/.test(p);
}

/** False when VARCHAR(10) truncated pbkdf2 or other corrupt storage. */
function isPinHashStorageValid(stored) {
  const s = stored != null ? String(stored) : "";
  if (!s) return true;
  if (!s.startsWith("pbkdf2:")) return true;
  const parts = s.split(":");
  return parts.length === 4 && parts[3].length >= 32;
}

function hashPin(pin) {
  const normalized = String(pin || "").trim();
  if (!isValidPinFormat(normalized)) {
    throw new Error("PIN must be 4 to 6 digits");
  }
  const salt = crypto.randomBytes(16).toString("hex");
  const hash = crypto
    .pbkdf2Sync(normalized, salt, PBKDF2_ITERATIONS, PBKDF2_KEYLEN, PBKDF2_DIGEST)
    .toString("hex");
  return `pbkdf2:${PBKDF2_ITERATIONS}:${salt}:${hash}`;
}

function verifyUserPin(userRow, providedPin) {
  const stored = userRow?.pin != null ? String(userRow.pin) : "";
  const pin = String(providedPin || "").trim();
  if (!stored || !pin) return false;
  if (!isValidPinFormat(pin)) return false;

  if (stored.startsWith("pbkdf2:")) {
    if (!isPinHashStorageValid(stored)) return false;
    const parts = stored.split(":");
    if (parts.length !== 4) return false;
    const iterations = Number(parts[1]);
    const salt = parts[2];
    const expected = parts[3];
    const actual = crypto
      .pbkdf2Sync(pin, salt, iterations, PBKDF2_KEYLEN, PBKDF2_DIGEST)
      .toString("hex");
    if (actual.length !== expected.length) return false;
    return crypto.timingSafeEqual(Buffer.from(actual), Buffer.from(expected));
  }

  // Legacy plain-text PIN (migrate on successful login).
  return stored === pin;
}

/** Re-hash legacy plain PIN to pbkdf2 after successful verify. */
async function upgradePinHashIfNeeded(pool, userId, providedPin) {
  const [rows] = await pool.query("SELECT pin FROM users WHERE id = ? LIMIT 1", [userId]);
  const stored = rows[0]?.pin != null ? String(rows[0].pin) : "";
  if (stored && stored.startsWith("pbkdf2:") && isPinHashStorageValid(stored)) return;
  const hashed = hashPin(providedPin);
  await pool.query("UPDATE users SET pin = ? WHERE id = ?", [hashed, userId]);
}

/** After save, confirm round-trip (catches truncated users.pin column). */
function assertPinSavedCorrectly(userRow, plainPin) {
  if (!verifyUserPin(userRow, plainPin)) {
    const len = userRow?.pin != null ? String(userRow.pin).length : 0;
    const err = new Error(
      `PIN verify-after-save failed (stored length ${len}). Run: ALTER TABLE users MODIFY pin VARCHAR(255);`
    );
    err.code = "PIN_STORAGE_CORRUPT";
    throw err;
  }
}

/** Clear truncated pbkdf2 rows so user can OTP-reset again. */
async function repairCorruptedPinHashes(pool) {
  const [r] = await pool.query(`
    UPDATE users
    SET pin = ''
    WHERE pin LIKE 'pbkdf2:%' AND CHAR_LENGTH(pin) < 80
  `);
  const n = r.affectedRows || 0;
  if (n > 0) {
    console.warn(`[pinAuth] Cleared ${n} corrupted pin hash(es) — users must OTP-reset PIN again`);
  }
  return n;
}

module.exports = {
  hashPin,
  verifyUserPin,
  upgradePinHashIfNeeded,
  isValidPinFormat,
  isPinHashStorageValid,
  assertPinSavedCorrectly,
  repairCorruptedPinHashes,
};
