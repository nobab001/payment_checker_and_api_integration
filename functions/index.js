"use strict";

const { setGlobalOptions }         = require("firebase-functions");
const { onCall, HttpsError }       = require("firebase-functions/v2/https");
const admin                        = require("firebase-admin");
const nodemailer                   = require("nodemailer");

admin.initializeApp();
setGlobalOptions({ maxInstances: 10 });

const db = admin.firestore();

// ─── constants ───────────────────────────────────────────────────────────────

const OTP_EXPIRY_MS      = 10 * 60 * 1000;       // 10 minutes
const RATE_LIMIT_MS      = 60 * 1000;             // 60 seconds between resends
const MAX_ATTEMPTS       = 5;                     // wrong guesses before lockout
const PENDING_REG_TTL_MS = 24 * 60 * 60 * 1000;  // reuse pending-reg UID for 24 h

// ─── input helpers ───────────────────────────────────────────────────────────

/** 11-digit Bangladeshi phone */
function isPhone(c) { return /^\d{11}$/.test(c); }

/** @gmail.com address */
function isGmail(c) { return /^[^\s@]+@gmail\.com$/i.test(c); }

/** Firestore-safe document key from a contact (replaces @ and .) */
function contactKey(c) { return c.replace(/[@.]/g, "_"); }

/** Cryptographically adequate 6-digit OTP */
function generateOtp() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

// ─── config loader ────────────────────────────────────────────────────────────

async function loadConfig() {
  const [gSnap, eSnap, gwSnap] = await Promise.all([
    db.doc("config/global").get(),
    db.doc("config/emailConfig").get(),
    db.collection("sms_gateways").where("isActive", "==", true).limit(1).get(),
  ]);
  return {
    global:        gSnap.data() || {},
    emailConfig:   eSnap.data() || {},
    activeGateway: gwSnap.empty ? null : gwSnap.docs[0].data(),
  };
}

// ─── Firestore user lookup ────────────────────────────────────────────────────

/**
 * Returns { uid, phone, email, blocked, ... } or null.
 * Searches by 'phone' or 'email' field depending on contact type.
 */
async function findUser(contact) {
  const field = isPhone(contact) ? "phone" : "email";
  const snap  = await db.collection("users")
    .where(field, "==", contact)
    .limit(1)
    .get();
  if (snap.empty) return null;
  return { uid: snap.docs[0].id, ...snap.docs[0].data() };
}

// ─── SMS delivery ─────────────────────────────────────────────────────────────
//
// Uses the active gateway from sms_gateways collection (isActive == true).
// Admin adds/activates gateways in the Admin App → SMS tab.
//
// Gateway endpoint is a URL template with placeholders:
//   {apiKey}    → gateway.apiKey
//   {phone}     → destination phone
//   {message}   → OTP message text
//   {senderId}  → gateway.senderId (optional)
//
// Example (BulkSMSBD):
//   https://bulksmsbd.net/api/smsapi?api_key={apiKey}&type=text&number={phone}&senderid={senderId}&message={message}
//
// Example (SMS.net.bd):
//   https://api.sms.net.bd/sendsms?api_key={apiKey}&msg={message}&to={phone}

async function sendSms(gateway, phone, message) {
  if (!gateway?.endpoint || !gateway?.apiKey) {
    throw new Error("No active SMS gateway configured");
  }
  const url = gateway.endpoint
    .replace(/\{apiKey\}/g,   encodeURIComponent(gateway.apiKey))
    .replace(/\{phone\}/g,    encodeURIComponent(phone))
    .replace(/\{message\}/g,  encodeURIComponent(message))
    .replace(/\{senderId\}/g, encodeURIComponent(gateway.senderId || ""));

  const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
  if (!res.ok) throw new Error(`SMS API HTTP ${res.status}`);
}

// ─── Gmail SMTP delivery ──────────────────────────────────────────────────────
//
// Uses Gmail SMTP with App Password stored in config/emailConfig:
//   gmailAddress  – the sender Gmail account (e.g. noreply@gmail.com)
//   appPassword   – 16-char Google App Password

async function sendGmail(emailConfig, to, otp) {
  const { gmailAddress, appPassword } = emailConfig;
  if (!gmailAddress || !appPassword) throw new Error("Gmail SMTP not configured");

  const transport = nodemailer.createTransport({
    service: "gmail",
    auth: { user: gmailAddress, pass: appPassword },
  });

  await transport.sendMail({
    from:    `"Payment Checker" <${gmailAddress}>`,
    to,
    subject: "আপনার OTP কোড - Payment Checker",
    html: `
      <div style="font-family:sans-serif;max-width:480px;margin:auto;padding:24px;
                  border:1px solid #e0e0e0;border-radius:12px">
        <h2 style="color:#1565C0;margin:0 0 12px">Payment Checker</h2>
        <p style="color:#444;margin:0 0 8px">আপনার একবার ব্যবহারযোগ্য যাচাইকরণ কোড:</p>
        <div style="font-size:40px;font-weight:bold;letter-spacing:12px;
                    color:#1565C0;padding:20px 0;text-align:center;
                    background:#f0f4ff;border-radius:8px;margin:16px 0">
          ${otp}
        </div>
        <p style="color:#666;margin:0 0 4px">
          এই কোডটি <strong>১০ মিনিট</strong> পর্যন্ত বৈধ।
        </p>
        <p style="color:#999;font-size:12px;margin:0">
          এই কোড কারো সাথে শেয়ার করবেন না।
        </p>
      </div>
    `,
  });
}

// ─── pending-registration UID deduplication ───────────────────────────────────
//
// When a new user verifies OTP we create a Firebase Auth user.  If they
// abandon registration and come back, we reuse the same UID (within 24 h)
// instead of leaking orphaned Auth accounts.
// Stored in:  pending_registrations/{contactKey}  →  { uid, createdAt }

async function createOrReuseAuthUser(key) {
  const ref  = db.doc(`pending_registrations/${key}`);
  const snap = await ref.get();

  if (snap.exists) {
    const { uid, createdAt } = snap.data();
    const age = Date.now() - (createdAt?.toMillis?.() ?? 0);
    if (age < PENDING_REG_TTL_MS) {
      try {
        await admin.auth().getUser(uid);
        return uid;                          // still valid — reuse it
      } catch (_) { /* Auth user was deleted externally; create fresh */ }
    }
  }

  const authUser = await admin.auth().createUser({});
  await ref.set({
    uid:       authUser.uid,
    createdAt: admin.firestore.Timestamp.now(),
  });
  return authUser.uid;
}

// ─── sendOtp ──────────────────────────────────────────────────────────────────
//
// Called by Flutter: FirebaseFunctions.instance.httpsCallable('sendOtp')
//                      .call({ contact: phoneOrEmail })
//
// Flow:
//   1. Validate input (11-digit phone or @gmail.com)
//   2. Rate-limit: one OTP per 60 s per contact
//   3. Load config; check if user is blocked
//   4. Generate OTP, write to otps/{contactKey}
//   5. SMS  → if contact is phone   AND smsApiEnabled
//   6. Email→ if email is known     AND gmailApiEnabled
//      (contact IS email, or existing phone-user has email on record)
//   7. If no channel delivered → delete OTP, throw failed-precondition

exports.sendOtp = onCall(async (req) => {
  const contact = String(req.data.contact ?? "").trim();

  if (!isPhone(contact) && !isGmail(contact)) {
    throw new HttpsError("invalid-argument",
      "Provide an 11-digit phone number or a @gmail.com address");
  }

  // ── rate limit ──────────────────────────────────────────────────────────
  const key    = contactKey(contact);
  const otpRef = db.doc(`otps/${key}`);
  const otpSnap = await otpRef.get();

  if (otpSnap.exists) {
    const sentMs = otpSnap.data().createdAt?.toMillis?.() ?? 0;
    if (Date.now() - sentMs < RATE_LIMIT_MS) {
      throw new HttpsError("resource-exhausted",
        "Please wait 60 seconds before requesting another OTP");
    }
  }

  // ── load config + user in parallel ──────────────────────────────────────
  const [cfg, user] = await Promise.all([loadConfig(), findUser(contact)]);
  const { global: g, emailConfig, activeGateway } = cfg;

  if (user?.blocked) {
    throw new HttpsError("permission-denied", "This account has been blocked");
  }

  // ── generate & store OTP ─────────────────────────────────────────────────
  const otp = generateOtp();
  await otpRef.set({
    otp,
    contact,
    createdAt: admin.firestore.Timestamp.now(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + OTP_EXPIRY_MS),
    used:      false,
    attempts:  0,
    isNewUser: !user,
  });

  const errors    = [];
  let   delivered = false;

  // ── SMS channel ──────────────────────────────────────────────────────────
  if (isPhone(contact) && g.smsApiEnabled !== false) {
    try {
      await sendSms(activeGateway, contact,
        `Payment Checker OTP: ${otp}. Valid 10 min. Do not share.`);
      delivered = true;
    } catch (e) {
      errors.push(`SMS: ${e.message}`);
    }
  }

  // ── Gmail channel ────────────────────────────────────────────────────────
  // Contact is email   → send to that address
  // Contact is phone   → send to user's registered email (if any)
  const emailTarget = isGmail(contact) ? contact : (user?.email ?? "");
  if (emailTarget && g.gmailApiEnabled !== false) {
    try {
      await sendGmail(emailConfig, emailTarget, otp);
      delivered = true;
    } catch (e) {
      errors.push(`Gmail: ${e.message}`);
    }
  }

  // ── no channel succeeded ─────────────────────────────────────────────────
  if (!delivered) {
    await otpRef.delete();
    throw new HttpsError("failed-precondition",
      errors.length ? errors.join("; ") : "No delivery channel is enabled");
  }

  return { sent: true };
});

// ─── verifyOtp ────────────────────────────────────────────────────────────────
//
// Called by Flutter: FirebaseFunctions.instance.httpsCallable('verifyOtp')
//                      .call({ contact, code })
//
// Returns: { token: string, isNewUser: boolean }
//
// Flow:
//   1. Validate args
//   2. Load OTP doc; check used / expired / attempt count
//   3. Compare code (wrong → increment attempts; too many → lock + throw)
//   4. Mark OTP used
//   5. Re-check Firestore for current user state (fresh read)
//   6. Existing user  → use their UID; check blocked
//      New user       → createOrReuseAuthUser (deduplicates abandoned sign-ups)
//   7. Create Firebase custom token
//   8. Return { token, isNewUser }

exports.verifyOtp = onCall(async (req) => {
  const contact = String(req.data.contact ?? "").trim();
  const code    = String(req.data.code    ?? "").trim();

  if (!contact || !code) {
    throw new HttpsError("invalid-argument", "contact and code are required");
  }

  // ── load OTP record ──────────────────────────────────────────────────────
  const key    = contactKey(contact);
  const otpRef = db.doc(`otps/${key}`);
  const snap   = await otpRef.get();

  if (!snap.exists) {
    throw new HttpsError("not-found", "OTP not found — please request a new one");
  }

  const data = snap.data();

  if (data.used) {
    throw new HttpsError("already-exists", "This OTP has already been used");
  }

  if (Date.now() > (data.expiresAt?.toMillis?.() ?? 0)) {
    throw new HttpsError("deadline-exceeded", "OTP expired — please request a new one");
  }

  const attempts = (data.attempts ?? 0) + 1;
  if (attempts > MAX_ATTEMPTS) {
    await otpRef.update({ used: true });
    throw new HttpsError("resource-exhausted",
      "Too many incorrect attempts — please request a new OTP");
  }

  // ── code check ───────────────────────────────────────────────────────────
  if (data.otp !== code) {
    await otpRef.update({ attempts });
    throw new HttpsError("invalid-argument", "Incorrect OTP");
  }

  // ── mark used ────────────────────────────────────────────────────────────
  await otpRef.update({ used: true, usedAt: admin.firestore.Timestamp.now() });

  // ── resolve UID ──────────────────────────────────────────────────────────
  // Always re-read Firestore — user state may have changed since sendOtp.
  const user      = await findUser(contact);
  const isNewUser = !user;
  let   uid;

  if (user) {
    if (user.blocked) {
      throw new HttpsError("permission-denied", "This account has been blocked");
    }
    uid = user.uid;
  } else {
    uid = await createOrReuseAuthUser(key);
  }

  const token = await admin.auth().createCustomToken(uid);
  return { token, isNewUser };
});

// ─── bKash wallet (admin config → secrets stay server-side) ──────────────────

function bkashBasePath(testMode) {
  return testMode !== false
    ? "https://tokenized.sandbox.bka.sh/v1.2.0-beta/tokenized/checkout"
    : "https://tokenized.pay.bka.sh/v1.2.0-beta/tokenized/checkout";
}

async function bkashGrantToken(ps) {
  const base = bkashBasePath(ps.testMode);
  const res = await fetch(`${base}/token/grant`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      username: String(ps.bkashApiKey || ""),
      password: String(ps.bkashPassword || ""),
    },
    body: JSON.stringify({
      app_key: String(ps.bkashApiKey || ""),
      app_secret: String(ps.bkashSecretKey || ""),
    }),
  });
  const text = await res.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch (_) {
    data = {};
  }
  if (!res.ok) {
    throw new HttpsError("failed-precondition", `bKash grant HTTP ${res.status}: ${text}`);
  }
  const idToken = data.id_token || data.idToken;
  if (!idToken) {
    throw new HttpsError(
      "failed-precondition",
      data.statusMessage || data.message || text || "bKash grant failed",
    );
  }
  return { idToken, base };
}

async function bkashCreatePayment(ps, idToken, base, amount, callbackURL, invoice) {
  const res = await fetch(`${base}/create`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: idToken,
      "X-APP-Key": String(ps.bkashAppId || ""),
    },
    body: JSON.stringify({
      mode: "0011",
      payerReference: " ",
      callbackURL: callbackURL || "https://www.bkash.com/",
      amount: String(amount),
      currency: "BDT",
      intent: "sale",
      merchantInvoiceNumber: invoice,
    }),
  });
  const text = await res.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch (_) {
    throw new HttpsError("failed-precondition", `bKash create not JSON: ${text}`);
  }
  if (!res.ok) {
    throw new HttpsError("failed-precondition", `bKash create HTTP ${res.status}: ${text}`);
  }
  const statusMsg = data.statusMessage || data.message;
  if (statusMsg && statusMsg !== "Successful") {
    throw new HttpsError("failed-precondition", statusMsg);
  }
  const bkashURL = data.bkashURL || data.bkashUrl;
  const paymentID = data.paymentID || data.payment_id;
  if (!bkashURL || !paymentID) {
    throw new HttpsError("failed-precondition", `bKash create missing url/id: ${text}`);
  }
  return { bkashURL, paymentID };
}

async function bkashExecutePayment(ps, idToken, base, paymentID) {
  const res = await fetch(`${base}/execute`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: idToken,
      "X-APP-Key": String(ps.bkashAppId || ""),
    },
    body: JSON.stringify({ paymentID }),
  });
  const text = await res.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch (_) {
    throw new HttpsError("failed-precondition", `bKash execute not JSON: ${text}`);
  }
  if (!res.ok) {
    throw new HttpsError("failed-precondition", `bKash execute HTTP ${res.status}: ${text}`);
  }
  return data;
}

exports.startWalletTopUp = onCall(async (req) => {
  if (!req.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const amount = Number(req.data.amount);
  if (!(amount >= 10 && amount <= 500000)) {
    throw new HttpsError("invalid-argument", "Amount must be between 10 and 500000");
  }
  const snap = await db.doc("config/paymentSettings").get();
  const ps = snap.data();
  if (!ps?.bkashApiKey || !ps?.bkashSecretKey || !ps?.bkashAppId || !ps?.bkashPassword) {
    throw new HttpsError("failed-precondition", "Configure bKash in Admin → Payment");
  }
  const uid = req.auth.uid;
  const invoice = `W_${uid.slice(0, 8)}_${Date.now()}`;
  const { idToken, base } = await bkashGrantToken(ps);
  const cb = String(ps.bkashCallbackUrl || "").trim() || "https://www.bkash.com/";
  const { bkashURL, paymentID } = await bkashCreatePayment(
    ps,
    idToken,
    base,
    amount,
    cb,
    invoice,
  );
  const pendingRef = await db.collection("wallet_topups").add({
    uid,
    amount,
    status: "pending",
    merchantInvoiceNumber: invoice,
    paymentID,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { bkashURL, paymentID, pendingId: pendingRef.id };
});

exports.completeWalletTopUp = onCall(async (req) => {
  if (!req.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const pendingId = String(req.data.pendingId || "").trim();
  const paymentID = String(req.data.paymentID || "").trim();
  if (!pendingId || !paymentID) {
    throw new HttpsError("invalid-argument", "pendingId and paymentID required");
  }
  const pref = db.collection("wallet_topups").doc(pendingId);
  const doc = await pref.get();
  if (!doc.exists) {
    throw new HttpsError("not-found", "Pending payment not found");
  }
  const p = doc.data();
  if (p.uid !== req.auth.uid) {
    throw new HttpsError("permission-denied", "Not your payment");
  }
  if (p.status !== "pending") {
    throw new HttpsError("failed-precondition", "Payment already processed");
  }
  if (String(p.paymentID) !== paymentID) {
    throw new HttpsError("invalid-argument", "paymentID does not match");
  }
  const snap = await db.doc("config/paymentSettings").get();
  const ps = snap.data();
  if (!ps?.bkashApiKey) {
    throw new HttpsError("failed-precondition", "Payment settings missing");
  }
  const { idToken, base } = await bkashGrantToken(ps);
  const exec = await bkashExecutePayment(ps, idToken, base, paymentID);
  const ok =
    exec.transactionStatus === "Completed" ||
    exec.statusCode === "0000" ||
    exec.statusMessage === "Successful";
  if (!ok) {
    throw new HttpsError(
      "failed-precondition",
      exec.statusMessage || exec.errorMessage || "Payment not completed",
    );
  }
  await db.runTransaction(async (t) => {
    const pr = await t.get(pref);
    if (!pr.exists || pr.data().status !== "pending") return;
    const uref = db.collection("users").doc(req.auth.uid);
    t.update(uref, {
      walletBalance: admin.firestore.FieldValue.increment(Number(p.amount)),
    });
    t.update(pref, {
      status: "completed",
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return { ok: true };
});

/** Tune BDT prices here or later load from Firestore. */
const HISTORY_PLANS = {
  history_10d: { days: 10, price: 100 },
  history_15d: { days: 15, price: 150 },
};

exports.purchaseHistorySubscription = onCall(async (req) => {
  if (!req.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const planId = String(req.data.planId || "");
  const plan = HISTORY_PLANS[planId];
  if (!plan) {
    throw new HttpsError("invalid-argument", "Invalid plan");
  }
  const uid = req.auth.uid;
  const uref = db.collection("users").doc(uid);
  await db.runTransaction(async (t) => {
    const us = await t.get(uref);
    if (!us.exists) {
      throw new HttpsError("not-found", "User not found");
    }
    const d = us.data();
    const bal = Number(d.walletBalance ?? 0);
    if (bal < plan.price) {
      throw new HttpsError(
        "failed-precondition",
        `Insufficient wallet (need ${plan.price} BDT)`,
      );
    }
    const cur = d.historyPremiumUntil;
    const curMs = cur?.toMillis?.() ?? 0;
    const baseMs = Math.max(curMs, Date.now());
    const newMs = baseMs + plan.days * 24 * 60 * 60 * 1000;
    t.update(uref, {
      walletBalance: admin.firestore.FieldValue.increment(-plan.price),
      historyPremiumUntil: admin.firestore.Timestamp.fromMillis(newMs),
    });
  });
  return { ok: true };
});
