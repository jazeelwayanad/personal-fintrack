// Developer-only CLI. Uses database credentials; no public inbox endpoint.
import { Client } from 'pg';
if (!process.env.DATABASE_URL) throw new Error('Set DATABASE_URL for the developer feedback inbox.');
const client = new Client({ connectionString: process.env.DATABASE_URL });
try {
  await client.connect();
  const { rows } = await client.query('SELECT f."createdAt", f.topic, f.message, f."appVersion", u.name, u.email FROM "Feedback" f JOIN "User" u ON u.id = f."userId" ORDER BY f."createdAt" DESC LIMIT 50');
  console.log(JSON.stringify(rows, null, 2));
} finally { await client.end(); }
