-- ============================================================
-- Payment Checker OTP System — Database Schema
-- ============================================================
-- Run this in phpMyAdmin → SQL tab, or via MySQL CLI:
--   mysql -u root -p < schema.sql
--
-- If the tables already exist the CREATE TABLE IF NOT EXISTS
-- statements are safe to re-run.  Use the ALTER TABLE section
-- at the bottom to upgrade an existing installation.
-- ============================================================


-- ============================================================
-- USERS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
  id               INT AUTO_INCREMENT PRIMARY KEY,
  name             VARCHAR(255)  NOT NULL DEFAULT '',
  phone            VARCHAR(20)   UNIQUE             COMMENT 'BD format: 01XXXXXXXXX',
  email            VARCHAR(255)  UNIQUE,
  password_hash    VARCHAR(255)  NOT NULL DEFAULT '' COMMENT 'Reserved for future PIN storage',
  profile_complete TINYINT(1)    NOT NULL DEFAULT 0  COMMENT '0 = new (must finish signup), 1 = onboarding done',
  created_at       TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  INDEX idx_phone (phone),
  INDEX idx_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- OTPS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS otps (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  contact    VARCHAR(255) NOT NULL  COMMENT 'Phone (01XXXXXXXXX) or Email address',
  code       VARCHAR(10)  NOT NULL,
  expires_at DATETIME     NOT NULL,
  used_at    DATETIME     DEFAULT NULL COMMENT 'NULL = not yet used',
  created_at TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,

  INDEX idx_contact       (contact),
  INDEX idx_code_contact  (code, contact),
  INDEX idx_expires       (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- UPGRADE: add profile_complete to an EXISTING users table
-- (safe to run even if column already exists — MySQL 8+ only)
-- ============================================================
-- ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_complete TINYINT(1) NOT NULL DEFAULT 0;


-- ============================================================
-- AUTH: multi-credential + device lock (see migrations/002_*.sql)
-- ============================================================
-- user_credentials: many phones/emails per account (max 5 each, app-enforced)
-- user_devices:     global UNIQUE(device_id) — one device → one account
--
-- Full DDL + backfill: server/migrations/002_multi_credential_device_lock.sql
-- Runtime init:        server/services/authSchemaInit.js (on server start)


-- ============================================================
-- OPTIONAL: settings table (not required by the Node server)
-- ============================================================
-- CREATE TABLE IF NOT EXISTS settings (
--   setting_key   VARCHAR(64) PRIMARY KEY,
--   setting_value TEXT,
--   updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
