"use strict";

const { createPool } = require("../lib/store");

async function main() {
  const pool = createPool();
  try {
    const result = await pool.query(`
      SELECT current_database() AS database, now() AS checked_at,
             (SELECT count(*)::int FROM courses) AS courses,
             (SELECT count(*)::int FROM learners) AS learners,
             (SELECT count(*)::int FROM quiz_attempts) AS attempts
    `);
    console.log(JSON.stringify({ status: "ok", ...result.rows[0] }));
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(`Caldova database verification failed: ${error.message}`);
  process.exitCode = 1;
});
