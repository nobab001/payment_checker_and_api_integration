"use strict";

/**
 * Creates user_credentials / user_devices and backfills from legacy tables.
 */
async function ensurePinColumn(pool) {
  const { repairCorruptedPinHashes } = require("../utils/pinAuth");
  try {
    await pool.query(`
      ALTER TABLE users
      ADD COLUMN pin VARCHAR(255) NOT NULL DEFAULT ''
    `);
  } catch (e) {
    if (e.code !== "ER_DUP_FIELDNAME") throw e;
  }
  try {
    await pool.query(`
      ALTER TABLE users
      MODIFY COLUMN pin VARCHAR(255) NOT NULL DEFAULT ''
    `);
    const [[col]] = await pool.query(`
      SELECT CHARACTER_MAXIMUM_LENGTH AS maxlen
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'pin'
    `);
    const maxlen = col?.maxlen != null ? Number(col.maxlen) : 0;
    console.log(`[ensurePinColumn] users.pin max length = ${maxlen}`);
    if (maxlen > 0 && maxlen < 64) {
      console.error(
        "[ensurePinColumn] users.pin is too short for pbkdf2 hashes — run migrations/003_pin_column_varchar255.sql"
      );
    }
  } catch (e) {
    console.warn("[ensurePinColumn] MODIFY pin:", e.message || e);
  }
  await repairCorruptedPinHashes(pool);
}

async function initAuthCredentialTables(pool) {
  await ensurePinColumn(pool);

  try {
    await pool.query(`
      ALTER TABLE users
      ADD COLUMN status ENUM('active', 'blocked') NOT NULL DEFAULT 'active'
    `);
  } catch (e) {
    if (e.code !== "ER_DUP_FIELDNAME") throw e;
  }

  await pool.query(`
    UPDATE users SET status = 'blocked' WHERE blocked = 1 AND status = 'active'
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS user_credentials (
      id          INT AUTO_INCREMENT PRIMARY KEY,
      user_id     INT NOT NULL,
      type        ENUM('phone', 'email') NOT NULL,
      value       VARCHAR(255) NOT NULL,
      verified_at DATETIME DEFAULT NULL,
      created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_cred_value (value),
      INDEX idx_cred_user_type (user_id, type),
      CONSTRAINT fk_cred_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS user_devices (
      id         INT AUTO_INCREMENT PRIMARY KEY,
      user_id    INT NOT NULL,
      device_id  VARCHAR(255) NOT NULL,
      last_login TIMESTAMP NULL DEFAULT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_auth_device (device_id),
      INDEX idx_ud_user (user_id),
      CONSTRAINT fk_ud_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await pool.query(`
    INSERT IGNORE INTO user_credentials (user_id, type, value, verified_at)
    SELECT id, 'phone', phone, COALESCE(updated_at, created_at)
    FROM users WHERE phone IS NOT NULL AND phone <> ''
  `);

  await pool.query(`
    INSERT IGNORE INTO user_credentials (user_id, type, value, verified_at)
    SELECT id, 'email', email, COALESCE(updated_at, created_at)
    FROM users WHERE email IS NOT NULL AND email <> ''
  `);

  await pool.query(`
    INSERT IGNORE INTO user_devices (user_id, device_id, last_login)
    SELECT d.user_id, d.device_id, COALESCE(d.last_seen_at, d.created_at)
    FROM devices d
    INNER JOIN (
      SELECT device_id, MIN(id) AS min_id FROM devices GROUP BY device_id
    ) first ON first.min_id = d.id
  `);
}

module.exports = { initAuthCredentialTables, ensurePinColumn };
