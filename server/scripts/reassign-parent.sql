-- Manual parent reassignment (MySQL / MariaDB)
-- Parent status lives in `devices.is_parent` (NOT Firebase).
--
-- Prefer (from repo root, uses .env DB_*):
--   node server/scripts/reassign-parent-cli.js --phone 01XXXXXXXXX --model MT2111
--
-- Or API from any logged-in phone:
--   POST /api/devices/reassign-parent  body: { "pin": "<signup PIN>", "target_device_model": "MT2111" }
--
-- 1) List devices for your account (replace phone or user id):
SELECT d.id, d.user_id, u.phone, d.device_id, d.device_name, d.device_model,
       d.status, d.is_parent, d.last_seen_at
FROM devices d
JOIN users u ON u.id = d.user_id
WHERE u.phone = '01XXXXXXXXX'   -- your login phone
ORDER BY d.is_parent DESC, d.id;

-- 2) Clear parent on ALL devices for that user (replace USER_ID):
-- UPDATE devices SET is_parent = 0 WHERE user_id = USER_ID;

-- 3) Set OnePlus (MT2111) as parent (replace USER_ID):
-- UPDATE devices SET is_parent = 1
-- WHERE user_id = USER_ID
--   AND device_model LIKE '%MT2111%'
-- LIMIT 1;

-- One-shot example for user_id = 5, OnePlus model MT2111:
-- START TRANSACTION;
-- UPDATE devices SET is_parent = 0 WHERE user_id = 5;
-- UPDATE devices SET is_parent = 1 WHERE user_id = 5 AND device_model LIKE '%MT2111%' LIMIT 1;
-- COMMIT;

-- Verify exactly one parent per user:
-- SELECT user_id, SUM(is_parent) AS parent_count FROM devices GROUP BY user_id HAVING parent_count <> 1;
