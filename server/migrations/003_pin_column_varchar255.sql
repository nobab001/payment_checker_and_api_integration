-- users.pin must hold pbkdf2 hashes (~100+ chars). VARCHAR(10) truncates and breaks verify.
ALTER TABLE users
  MODIFY COLUMN pin VARCHAR(255) NOT NULL DEFAULT '';
