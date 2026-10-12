"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { getQuizAvailability, getQuizMode } = require("../lib/quiz-mode");

test("quiz mode defaults to available", () => {
  assert.equal(getQuizMode(undefined), "available");
  assert.deepEqual(getQuizAvailability(undefined), { available: true, mode: "available" });
});

test("quiz mode exposes a symptom-only unavailable response", () => {
  const result = getQuizAvailability("unavailable");
  assert.equal(result.available, false);
  assert.equal(result.statusCode, 503);
  assert.equal(result.body.error, "quiz_temporarily_unavailable");
  assert.doesNotMatch(JSON.stringify(result.body), /configuration|environment|database|credential/i);
});
