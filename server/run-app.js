const fs = require('fs');

console.log('=== Starting run-app.js ===');

// Create log file first
const logPath = 'd:/payment_checker/server/debug.log';
fs.writeFileSync(logPath, '=== Starting app.js ===\n');

// Redirect console to file
const logFile = fs.createWriteStream(logPath, { flags: 'a' });
console.log = (...args) => {
  const msg = args.map(a => typeof a === 'object' ? JSON.stringify(a) : String(a)).join(' ');
  logFile.write(msg + '\n');
  process.stdout.write(msg + '\n');
};
console.error = console.log;

process.env.NODE_ENV = 'test';

try {
  console.log('About to require app.js...');
  require('D:/payment_checker/server/app.js');
  console.log('app.js loaded successfully');
} catch(e) {
  const msg = 'FAILED: ' + e.message + '\n' + e.stack;
  fs.appendFileSync(logPath, msg + '\n');
  console.error(msg);
  process.exit(1);
}

console.log('Script complete');