-- MariaDB schema: users, otps, sms_settings
-- Run in CloudPanel → Databases → phpMyAdmin (or mysql CLI), then sync data as needed.

CREATE TABLE IF NOT EXISTS users (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  phone VARCHAR(32) NULL DEFAULT NULL,
  email VARCHAR(255) NULL DEFAULT NULL,
  name VARCHAR(255) NOT NULL DEFAULT '',
  role VARCHAR(32) NOT NULL DEFAULT 'user',
  pin VARCHAR(128) NOT NULL DEFAULT '',
  email_verified TINYINT(1) NOT NULL DEFAULT 0,
  blocked TINYINT(1) NOT NULL DEFAULT 0,
  balance DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  history_premium_until DATETIME NULL DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_users_phone (phone),
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS otps (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  phone VARCHAR(255) NOT NULL COMMENT 'login id: BD mobile OR @gmail.com (same column for both)',
  code VARCHAR(10) NOT NULL,
  expires_at DATETIME NOT NULL,
  used_at DATETIME NULL DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_otp_recipient_created (phone, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sms_settings (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  gateway_url TEXT NOT NULL COMMENT 'URL template: {apiKey} {phone} {message} {senderId}',
  http_method VARCHAR(10) NOT NULL DEFAULT 'GET' COMMENT 'GET or POST',
  post_body_template TEXT NULL COMMENT 'Optional JSON string for POST; same placeholders in values',
  api_key VARCHAR(512) NOT NULL DEFAULT '',
  sender_id VARCHAR(64) NOT NULL DEFAULT '',
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Example row (replace with your real gateway template and secrets):
-- INSERT INTO sms_settings (gateway_url, http_method, post_body_template, api_key, sender_id, is_active)
-- VALUES (
--   'https://example-sms-provider.test/send?key={apiKey}&to={phone}&from={senderId}&text={message}',
--   'GET',
--   NULL,
--   'your-api-key',
--   'your-sender-id',
--   1
-- );
