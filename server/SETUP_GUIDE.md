# OTP System Setup Guide

Complete step-by-step instructions for deploying the Payment Checker OTP System.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Database Setup (MySQL)](#database-setup-mysql)
3. [.env Configuration](#env-configuration)
4. [Terminal Commands (Before & After)](#terminal-commands-before--after)
5. [Gmail App Password Setup](#gmail-app-password-setup)
6. [SMS Gateway Configuration](#sms-gateway-configuration)
7. [VPS Deployment](#vps-deployment)
8. [Testing](#testing)

---

## Prerequisites

- Node.js v18+ installed
- MySQL 8.0+ running
- Domain (optional, for production)
- Gmail account (for OTP emails)
- SMS Gateway account (optional, for OTP SMS)

---

## Database Setup (MySQL)

### Option A: Using phpMyAdmin

1. **Access phpMyAdmin**
   ```
   http://your-server/phpmyadmin
   ```

2. **Create Database**
   - Click "New" in left sidebar
   - Name: `payment_checker`
   - Collation: `utf8mb4_unicode_ci`
   - Click "Create"

3. **Import Schema**
   - Select `payment_checker` database
   - Click "Import" tab
   - Choose `schema.sql` file from `/server/` folder
   - Scroll down and click "Go"

4. **Create Admin User (Optional)**
   ```sql
   -- Run in SQL tab:
   CREATE USER 'payment_api'@'localhost' IDENTIFIED BY 'your-strong-password';
   GRANT ALL PRIVILEGES ON payment_checker.* TO 'payment_api'@'localhost';
   FLUSH PRIVILEGES;
   ```

### Option B: Using MySQL CLI

```bash
# Connect to MySQL
mysql -u root -p

# Create database and tables
CREATE DATABASE payment_checker CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE payment_checker;

-- Paste the contents of schema.sql here
SOURCE /path/to/server/schema.sql;

# Create limited user (recommended for production)
CREATE USER 'payment_api'@'localhost' IDENTIFIED BY 'your-strong-password';
GRANT ALL PRIVILEGES ON payment_checker.* TO 'payment_api'@'localhost';
FLUSH PRIVILEGES;

EXIT;
```

---

## .env Configuration

Copy `.env.example` to `.env` and fill in your values:

```bash
# Database
DB_HOST=localhost
DB_PORT=3306
DB_USER=your_db_user
DB_PASSWORD=your_db_password
DB_NAME=payment_checker

# JWT (generate with: openssl rand -base64 64)
JWT_SECRET=your-very-long-random-secret-key-at-least-32-chars
JWT_EXPIRES_IN=7d

# OTP Settings
OTP_LENGTH=6
OTP_EXPIRY_MINUTES=5
OTP_RESEND_COOLDOWN_SEC=60

# Gmail (App Password, not regular password!)
GMAIL_USER=your-email@gmail.com
GMAIL_PASS=xxxx xxxx xxxx xxxx
GMAIL_FROM=your-email@gmail.com
GMAIL_OTP_SUBJECT=Payment Checker - Your Verification Code

# SMS Gateway (leave empty to disable)
SMS_API_URL=https://api.your-sms-provider.com/send
SMS_API_KEY=your_api_key
SMS_API_SECRET=your_api_secret
SMS_SENDER_ID=PayCheck

# Server
PORT=3000
NODE_ENV=production
CORS_ORIGIN=https://yourdomain.com
```

---

## Terminal Commands (Before & After)

### BEFORE Pasting Code

```bash
# Navigate to server directory
cd d:\payment_checker\server

# Install Node.js dependencies (if not done)
npm install

# Test database connection
mysql -u your_user -p -e "USE payment_checker; SELECT 1;"

# Check Node.js version (need v18+)
node --version
```

### AFTER Pasting Code

```bash
# Navigate to server directory
cd d:\payment_checker\server

# Install additional dependencies (if not in package.json)
npm install express mysql2 nodemailer axios jsonwebtoken dotenv cors helmet express-rate-limit

# Test the server (development)
npm run dev

# OR start in production
npm start

# For production, use PM2
npm install -g pm2
pm2 start app.js --name payment-otp
pm2 save
pm2 startup
```

---

## Gmail App Password Setup

1. **Enable 2-Factor Authentication**
   - Go to: https://myaccount.google.com/security
   - Enable "2-Step Verification"

2. **Generate App Password**
   - Go to: https://myaccount.google.com/apppasswords
   - Select app: "Mail"
   - Select device: "Other (Custom name)"
   - Name it: "Payment Checker OTP"
   - Copy the 16-character password

3. **Update .env**
   ```
   GMAIL_USER=your-email@gmail.com
   GMAIL_PASS=abcd efgh ijkl mnop  (16 chars, no spaces)
   ```

4. **Test Gmail sending**
   ```bash
   node -e "
   const nodemailer = require('nodemailer');
   const t = nodemailer.createTransport({
     service: 'gmail',
     auth: { user: 'YOUR_EMAIL', pass: 'YOUR_APP_PASSWORD' }
   });
   t.sendMail({ from: 'YOUR_EMAIL', to: 'TEST_EMAIL', subject: 'Test', text: 'Hello' })
     .then(() => console.log('OK'))
     .catch(e => console.error(e.message));
   "
   ```

---

## SMS Gateway Configuration

### Twilio Setup

```env
SMS_API_URL=https://api.twilio.com/2010-04-01/Accounts/YOUR_ACCOUNT_SID/Messages.json
SMS_API_KEY=YOUR_ACCOUNT_SID
SMS_API_SECRET=YOUR_AUTH_TOKEN
SMS_SENDER_ID=+1234567890
```

**Payload sent:**
```json
{
  "api_key": "YOUR_ACCOUNT_SID",
  "api_secret": "YOUR_AUTH_TOKEN",
  "sender_id": "+1234567890",
  "recipient": "01712345678",
  "message": "Payment Checker: 123456 is your verification code..."
}
```

### Bulk SMS BD (e.g., BulkSMSBD, SMS BD, etc.)

```env
SMS_API_URL=https://api.bulksmsbd.com/api/send
SMS_API_KEY=YOUR_API_KEY
SMS_API_SECRET=YOUR_API_SECRET
SMS_SENDER_ID=PayChk
```

### Generic API Format

The system sends a POST request to `SMS_API_URL` with:
```json
{
  "api_key": "...",
  "api_secret": "...",
  "sender_id": "...",
  "recipient": "01XXXXXXXXX",
  "message": "Payment Checker: 123456 is your verification code..."
}
```

**Expected success responses (any one):**
- `{"status": "success"}`
- `{"success": true}`
- `{"code": "200"}`
- HTTP 200-299 status

---

## VPS Deployment

### 1. Initial Server Setup

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Node.js 18+
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Install MySQL
sudo apt install -y mysql-server

# Secure MySQL installation
sudo mysql_secure_installation

# Install PM2 globally
sudo npm install -g pm2
```

### 2. Database Setup

```bash
# Create database
sudo mysql
```

```sql
CREATE DATABASE payment_checker CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'payment_api'@'localhost' IDENTIFIED BY 'your-strong-password';
GRANT ALL PRIVILEGES ON payment_checker.* TO 'payment_api'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### 3. Deploy Application

```bash
# Create app directory
sudo mkdir -p /var/www/payment-checker
sudo chown -R $USER:$USER /var/www/payment-checker

# Clone/copy your application
cd /var/www/payment-checker/server

# Install dependencies
npm install --production

# Create .env file
nano .env  # Paste your configuration

# Test run
node app.js

# If works, stop with Ctrl+C and start with PM2
pm2 start app.js --name payment-otp
pm2 save
pm2 startup  # Run the output command
```

### 4. Configure Nginx (Reverse Proxy)

```bash
sudo nano /etc/nginx/sites-available/payment-otp
```

```nginx
server {
    listen 80;
    server_name api.paychek.online;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_cache_bypass $http_upgrade;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/payment-otp /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

### 5. SSL Certificate (Let's Encrypt)

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d api.paychek.online
```

### 6. Firewall Setup

```bash
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
```

---

## Testing

### Flutter app: login and API reachability

The Flutter login screen calls `GET /health` on the configured API base URL before sending or verifying OTP. If the phone has no usable network interface, or the server is down, wrong host, or DNS fails, the app shows **Bengali** snackbar messages (mapped from `ApiException.code` in `ApiService` / `LoginScreen`).

**Checklist**

1. **Node API running** on the same host/port as in the app (default `http://127.0.0.1:3000` from [lib/utils/constants.dart](../lib/utils/constants.dart)).
2. **USB debugging:** run `adb reverse tcp:3000 tcp:3000` so the device’s `127.0.0.1:3000` reaches the PC.
3. **Custom base URL:** Profile → **SMS filter & forward** (override stored in SharedPreferences).
4. **Firewall** not blocking inbound connections to the API port.

### Health Check

```bash
# Local
curl http://localhost:3000/health

# Response
{
  "ok": true,
  "service": "Payment Checker OTP API",
  "database": "connected",
  "config": {
    "emailConfigured": true,
    "smsConfigured": false,
    "jwtConfigured": true
  }
}
```

### Test OTP Endpoints

**1. Send OTP for existing user:**
```bash
curl -X POST http://localhost:3000/api/send-otp \
  -H "Content-Type: application/json" \
  -d '{"contact": "01712345678"}'
```

**2. Send OTP for new user:**
```bash
curl -X POST http://localhost:3000/api/send-otp-new \
  -H "Content-Type: application/json" \
  -d '{"contact": "01712345678", "name": "Test User"}'
```

**3. Verify OTP:**
```bash
curl -X POST http://localhost:3000/api/verify-otp \
  -H "Content-Type: application/json" \
  -d '{"contact": "01712345678", "code": "123456"}'
```

**4. Expected responses:**

| Scenario | Response |
|----------|----------|
| User exists | `{"success": true, "message": "OTP sent via SMS"}` |
| User not found | `{"success": false, "error": "user_not_found", "showPopup": true}` |
| Rate limited | `{"success": false, "error": "rate_limited", "retryAfter": 45}` |
| Invalid OTP | `{"success": false, "error": "invalid_otp"}` |
| OTP verified | `{"success": true, "token": "eyJ...", "user": {...}}` |

---

## Frontend Integration

### Handle user_not_found popup

```javascript
async function handleSendOtp(contact) {
  try {
    const res = await fetch('/api/send-otp', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ contact })
    });
    const data = await res.json();
    
    if (data.showPopup) {
      // Show signup popup
      showPopup({
        title: data.popupTitle,
        message: data.popupMessage,
        action: data.popupAction,
        onConfirm: () => handleSignupNewUser(contact)
      });
      return;
    }
    
    if (data.success) {
      showOtpInput(contact, data.channel);
    }
  } catch (err) {
    showError('Failed to send OTP');
  }
}

async function handleSignupNewUser(contact) {
  // Call send-otp-new with name
  const name = await promptForName();
  const res = await fetch('/api/send-otp-new', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ contact, name })
  });
  const data = await res.json();
  
  if (data.success) {
    showOtpInput(contact, data.channel);
  }
}
```

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| `Gmail auth error` | Enable 2FA and generate App Password |
| `SMS not configured` | Set SMS_API_URL in .env |
| `DB connection failed` | Check DB credentials in .env |
| `Port in use` | Change PORT in .env or kill process |
| `CORS error` | Update CORS_ORIGIN in .env |

### Check Logs

```bash
# PM2 logs
pm2 logs payment-otp

# System logs
sudo journalctl -u nginx
sudo tail -f /var/log/mysql/error.log
```

### Restart Services

```bash
# Restart API
pm2 restart payment-otp

# Restart Nginx
sudo systemctl restart nginx

# Restart MySQL
sudo systemctl restart mysql
```

---

## Security Checklist

- [ ] Change JWT_SECRET to a strong random value
- [ ] Use MySQL limited user (not root)
- [ ] Enable SSL/HTTPS in production
- [ ] Set CORS_ORIGIN to specific domains
- [ ] Use Gmail App Password (not regular password)
- [ ] Keep Node.js and npm packages updated
- [ ] Enable firewall
- [ ] Regular backups of database