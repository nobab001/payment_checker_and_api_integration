try {
  require('./app.js');
} catch (e) {
  console.error('Error:', e.message);
  process.exit(1);
}
