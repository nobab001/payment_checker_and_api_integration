-- Multi-credential accounts + global device binding (user_credentials, user_devices)
-- Safe to re-run: uses IF NOT EXISTS / INSERT IGNORE where possible.

-- Account status (skip this ALTER if column `status` already exists)
ALTER TABLE users
  ADD COLUMN status ENUM('active', 'blocked') NOT NULL DEFAULT 'active';

UPDATE users SET status = 'blocked' WHERE blocked = 1 AND status = 'active';

-- ---------------------------------------------------------------------------
-- user_credentials — up to 5 phones + 5 emails per account (enforced in app)
-- ---------------------------------------------------------------------------
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- user_devices — one hardware device_id bound to exactly one account
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_devices (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    INT NOT NULL,
  device_id  VARCHAR(255) NOT NULL,
  last_login TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  UNIQUE KEY uniq_auth_device (device_id),
  INDEX idx_ud_user (user_id),
  CONSTRAINT fk_ud_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Backfill credentials from legacy users.phone / users.email
INSERT IGNORE INTO user_credentials (user_id, type, value, verified_at)
SELECT id, 'phone', phone, COALESCE(updated_at, created_at)
FROM users
WHERE phone IS NOT NULL AND phone <> '';

INSERT IGNORE INTO user_credentials (user_id, type, value, verified_at)
SELECT id, 'email', email, COALESCE(updated_at, created_at)
FROM users
WHERE email IS NOT NULL AND email <> '';

-- Backfill device locks from app `devices` table (earliest row wins per device_id)
INSERT IGNORE INTO user_devices (user_id, device_id, last_login)
SELECT d.user_id, d.device_id, COALESCE(d.last_seen_at, d.created_at)
FROM devices d
INNER JOIN (
  SELECT device_id, MIN(id) AS min_id
  FROM devices
  GROUP BY device_id
) first ON first.min_id = d.id;
