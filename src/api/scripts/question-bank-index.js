"use strict";

const { createPool } = require("../lib/store");
const {
  QUESTION_BANK_INDEX,
  CREATE_QUESTION_BANK_INDEX_SQL
} = require("../lib/scenario-controls");

async function main() {
  const action = process.argv[2];
  if (!["status", "drop", "recreate"].includes(action)) {
    throw new Error("Usage: node scripts/question-bank-index.js status|drop|recreate");
  }
  const pool = createPool();
  try {
    if (action === "drop") {
      await pool.query(`DROP INDEX IF EXISTS ${QUESTION_BANK_INDEX}`);
    } else if (action === "recreate") {
      await pool.query(CREATE_QUESTION_BANK_INDEX_SQL);
      await pool.query(`REINDEX INDEX ${QUESTION_BANK_INDEX}`);
      await pool.query("ANALYZE question_bank");
    }
    const result = await pool.query(
      "SELECT to_regclass($1) IS NOT NULL AS present",
      [`public.${QUESTION_BANK_INDEX}`]
    );
    console.log(JSON.stringify({
      action,
      index: QUESTION_BANK_INDEX,
      present: result.rows[0].present
    }));
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(`Question-bank index action failed: ${error.message}`);
  process.exitCode = 1;
});
