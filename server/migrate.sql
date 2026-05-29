-- ============================================================
-- Payment Checker — Migration Script
-- phpMyAdmin > payment_checker database > SQL tab-এ paste করুন
-- ============================================================

-- 1. users table-এ missing columns যোগ করুন
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS role              VARCHAR(20)   NOT NULL DEFAULT 'user',
  ADD COLUMN IF NOT EXISTS pin               VARCHAR(255)  NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS balance           DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS blocked           TINYINT(1)    NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS email_verified    TINYINT(1)    NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS history_premium_until DATETIME  DEFAULT NULL;

-- 2. sms_settings table তৈরি করুন
CREATE TABLE IF NOT EXISTS sms_settings (
  id                  INT AUTO_INCREMENT PRIMARY KEY,
  gateway_url         VARCHAR(512)  NOT NULL COMMENT 'SMS gateway base URL with placeholders',
  http_method         VARCHAR(10)   NOT NULL DEFAULT 'GET' COMMENT 'GET or POST',
  post_body_template  TEXT          DEFAULT NULL COMMENT 'JSON body template for POST (use {phone}, {message}, {apiKey}, {senderId})',
  api_key             VARCHAR(255)  DEFAULT NULL,
  sender_id           VARCHAR(50)   DEFAULT NULL,
  is_active           TINYINT(1)    NOT NULL DEFAULT 0,
  label               VARCHAR(100)  DEFAULT NULL COMMENT 'Friendly name e.g. BulkSMSBD',
  created_at          TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMP     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. BulkSMSBD gateway — is_active=1 so real SMS is sent (use ALLOW_OTP_WITHOUT_SMS=1 in .env only for local without SMS).
INSERT INTO sms_settings (gateway_url, http_method, api_key, sender_id, is_active, label)
VALUES (
  'http://bulksmsbd.net/api/smsapi?api_key={apiKey}&type=text&number={phone}&senderid={senderId}&message={message}',
  'GET',
  'hknDpPg0AazTNirpWyao',
  '8809617626944',
  1,
  'BulkSMSBD'
)
ON DUPLICATE KEY UPDATE id = id;

-- 4. If row already exists from older migration (is_active=0), turn SMS on:
UPDATE sms_settings SET is_active = 1 WHERE gateway_url LIKE '%bulksmsbd%';

-- 5. devices table (per-user hardware rows) + optional user label `custom_name`
--    (empty custom_name → app shows device_model, then device_name).
--    `status` pending/active for master–slave approval; `is_parent` marks account parent.
CREATE TABLE IF NOT EXISTS devices (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  device_id VARCHAR(255) NOT NULL,
  device_name VARCHAR(255) NOT NULL DEFAULT 'My Phone',
  custom_name VARCHAR(255) DEFAULT NULL,
  status ENUM('pending','active') NOT NULL DEFAULT 'pending',
  is_parent TINYINT(1) NOT NULL DEFAULT 0,
  device_model VARCHAR(255) NOT NULL DEFAULT '',
  android_version VARCHAR(64) NOT NULL DEFAULT '',
  sim1_number VARCHAR(32) DEFAULT NULL,
  sim1_operator VARCHAR(64) DEFAULT NULL,
  sim2_number VARCHAR(32) DEFAULT NULL,
  sim2_operator VARCHAR(64) DEFAULT NULL,
  sms_filter_enabled TINYINT(1) NOT NULL DEFAULT 1,
  block_unknown TINYINT(1) NOT NULL DEFAULT 0,
  block_incoming TINYINT(1) NOT NULL DEFAULT 0,
  allowed_keywords TEXT,
  blocked_keywords TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_user_device (user_id, device_id),
  INDEX idx_devices_user (user_id),
  CONSTRAINT fk_devices_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE devices
  ADD COLUMN IF NOT EXISTS custom_name VARCHAR(255) DEFAULT NULL AFTER device_name;
ALTER TABLE devices
  ADD COLUMN IF NOT EXISTS status ENUM('pending','active') NOT NULL DEFAULT 'active' AFTER custom_name;
ALTER TABLE devices
  ADD COLUMN IF NOT EXISTS is_parent TINYINT(1) NOT NULL DEFAULT 0 AFTER status;

-- 6. sms_templates — admin dynamic SMS rules (Customer Preview + formats JSON)
CREATE TABLE IF NOT EXISTS sms_templates (
  id INT AUTO_INCREMENT PRIMARY KEY,
  customer_preview VARCHAR(128) NOT NULL,
  sender_id VARCHAR(64) NOT NULL DEFAULT '',
  formats JSON NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_sms_templates_preview (customer_preview, is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 7. parsed_payments — structured payment SMS from Flutter (7 API fields)
CREATE TABLE IF NOT EXISTS parsed_payments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  device_id VARCHAR(255) DEFAULT NULL,
  sim_slot TINYINT DEFAULT NULL,
  sim_number VARCHAR(32) DEFAULT NULL COMMENT 'legacy alias of receiver_number',
  receiver_number VARCHAR(32) DEFAULT NULL COMMENT 'user SIM that received SMS',
  provider_tag VARCHAR(128) NOT NULL DEFAULT '' COMMENT 'e.g. bKash Personal',
  amount DECIMAL(12,2) NOT NULL DEFAULT 0,
  trx_id VARCHAR(64) NOT NULL DEFAULT '',
  sender_number VARCHAR(32) DEFAULT NULL COMMENT 'payer phone from SMS body',
  sms_timestamp DATETIME NOT NULL,
  sms_date DATE DEFAULT NULL,
  sms_time VARCHAR(16) DEFAULT NULL,
  raw_body TEXT COMMENT 'legacy alias of full_sms',
  full_sms TEXT NOT NULL COMMENT 'complete raw SMS text',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_parsed_user_time (user_id, sms_timestamp),
  INDEX idx_parsed_trx (user_id, trx_id),
  CONSTRAINT fk_parsed_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE parsed_payments ADD COLUMN IF NOT EXISTS receiver_number VARCHAR(32) DEFAULT NULL;
ALTER TABLE parsed_payments ADD COLUMN IF NOT EXISTS sms_date DATE DEFAULT NULL;
ALTER TABLE parsed_payments ADD COLUMN IF NOT EXISTS sms_time VARCHAR(16) DEFAULT NULL;
ALTER TABLE parsed_payments ADD COLUMN IF NOT EXISTS full_sms TEXT;

ALTER TABLE sms_records ADD COLUMN IF NOT EXISTS sim_slot TINYINT DEFAULT NULL;
ALTER TABLE sms_records ADD COLUMN IF NOT EXISTS sim_number VARCHAR(32) DEFAULT NULL;
ALTER TABLE sms_records ADD COLUMN IF NOT EXISTS provider_tag VARCHAR(64) DEFAULT NULL;
ALTER TABLE sms_records ADD COLUMN IF NOT EXISTS trx_id VARCHAR(64) DEFAULT NULL;
ALTER TABLE sms_records ADD COLUMN IF NOT EXISTS sender_number VARCHAR(32) DEFAULT NULL;
