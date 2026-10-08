"use strict";

const fs = require("node:fs/promises");
const path = require("node:path");
const { createPool } = require("../lib/store");

async function main() {
  const schemaPath = path.resolve(__dirname, "../db/schema.sql");
  const sql = await fs.readFile(schemaPath, "utf8");
  const pool = createPool();
  try {
    await pool.query(sql);
    const result = await pool.query(`
      SELECT
        (SELECT count(*)::int FROM courses) AS courses,
        (SELECT count(*)::int FROM learners) AS learners,
        (SELECT count(*)::int FROM assessments) AS assessments,
        (SELECT count(*)::int FROM quiz_questions) AS quiz_questions,
        (SELECT count(*)::int FROM quiz_attempts) AS quiz_attempts,
        (SELECT count(*)::int FROM reporting_exports) AS reporting_exports
    `);
    console.log(JSON.stringify({ status: "seeded", ...result.rows[0] }));
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(`Caldova seed failed: ${error.message}`);
  process.exitCode = 1;
});
