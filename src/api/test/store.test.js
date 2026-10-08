"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

process.env.CALDOVA_DATA_MODE = "memory";
const { createStore } = require("../lib/store");

test("memory baseline exposes coherent courses and assessments", async () => {
  const store = createStore();
  const summary = await store.summary();
  const courses = await store.courses();
  const quiz = await store.quiz("OPS-201-M1");

  assert.deepEqual(summary, { courses: 3, learners: 4, assessments: 3, attempts: 6 });
  assert.equal(courses.length, 3);
  assert.equal(quiz.course_id, "OPS-201");
  assert.equal(quiz.questions.length, 3);
  assert.equal("answer_idx" in quiz.questions[0], false);
});

test("memory submission records a deterministic score", async () => {
  const store = createStore();
  const result = await store.submit("OPS-201-M1", "LRN-1001", [1, 3, 2]);
  const summary = await store.summary();

  assert.equal(result.scorePct, 100);
  assert.equal(result.correct, 3);
  assert.equal(summary.attempts, 7);
});
