"use strict";

const QUESTION_BANK_INDEX = "idx_question_bank_assessment_active";
const QUESTION_BANK_LOOKUP_SQL = `
  SELECT count(*)::int AS available
  FROM generate_series(1, 240) AS sample
  CROSS JOIN LATERAL (
    SELECT id
    FROM question_bank
    WHERE assessment_id = $1
      AND active
      AND prompt = 'Caldova practice item ' || (1 + ((sample * 7919) % 120000))
    LIMIT 1
  ) AS matched
`;
const CREATE_QUESTION_BANK_INDEX_SQL = `
  CREATE INDEX IF NOT EXISTS ${QUESTION_BANK_INDEX}
  ON question_bank (assessment_id, prompt) WHERE active
`;

async function runQuestionBankLookup(client, assessmentId) {
  const result = await client.query(QUESTION_BANK_LOOKUP_SQL, [assessmentId]);
  return { rows: [{ available: result.rows[0]?.available ?? 0 }] };
}

async function withConnectionHold(client, milliseconds) {
  if (!Number.isFinite(milliseconds) || milliseconds <= 0) return;
  const bounded = Math.min(Math.round(milliseconds), 3000);
  await client.query("SELECT pg_sleep($1)", [bounded / 1000]);
}

module.exports = {
  QUESTION_BANK_INDEX,
  QUESTION_BANK_LOOKUP_SQL,
  CREATE_QUESTION_BANK_INDEX_SQL,
  runQuestionBankLookup,
  withConnectionHold
};
