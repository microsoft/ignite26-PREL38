"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  QUESTION_BANK_INDEX,
  QUESTION_BANK_LOOKUP_SQL,
  CREATE_QUESTION_BANK_INDEX_SQL,
  runQuestionBankLookup,
  withConnectionHold
} = require("../lib/scenario-controls");

test("question-bank lookup is tied to the one lab-created index", async () => {
  const calls = [];
  const client = {
    async query(sql, values) {
      calls.push({ sql, values });
      return { rows: [{ available: 3 }] };
    }
  };
  const result = await runQuestionBankLookup(client, "OPS-201-M1");
  assert.equal(result.rows[0].available, 3);
  assert.match(QUESTION_BANK_LOOKUP_SQL, /generate_series\(1, 240\)/);
  assert.match(QUESTION_BANK_LOOKUP_SQL, /assessment_id = \$1/);
  assert.match(CREATE_QUESTION_BANK_INDEX_SQL, new RegExp(QUESTION_BANK_INDEX));
  assert.deepEqual(calls[0].values, ["OPS-201-M1"]);
});

test("connection hold is bounded and disabled in the healthy baseline", async () => {
  const calls = [];
  const client = { async query(sql, values) { calls.push({ sql, values }); } };
  await withConnectionHold(client, 0);
  assert.equal(calls.length, 0);
  await withConnectionHold(client, 9000);
  assert.deepEqual(calls[0], { sql: "SELECT pg_sleep($1)", values: [3] });
});
