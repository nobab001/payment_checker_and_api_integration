require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });
const mysql = require("mysql2/promise");

(async () => {
  const pool = await mysql.createPool({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
  });
  const [users] = await pool.query(
    "SELECT id, email, phone FROM users ORDER BY id DESC LIMIT 5"
  );
  console.log("users:", users);
  const [devices] = await pool.query(
    "SELECT id, user_id, device_id, device_name, status, is_parent, last_seen_at FROM devices ORDER BY id DESC LIMIT 20"
  );
  console.log("devices:", devices);
  const [cols] = await pool.query(
    "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'devices' ORDER BY ORDINAL_POSITION"
  );
  console.log(
    "columns:",
    cols.map((c) => c.COLUMN_NAME).join(", ")
  );
  await pool.end();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
