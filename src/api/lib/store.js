"use strict";

const { Pool } = require("pg");
const { runQuestionBankLookup, withConnectionHold } = require("./scenario-controls");

const fixture = {
  courses: [
    { id: "OPS-201", title: "Reliable Cloud Operations", discipline: "Technology", units: 8, enrolled: 184 },
    { id: "DATA-215", title: "Applied Data Analysis", discipline: "Analytics", units: 10, enrolled: 146 },
    { id: "BUS-140", title: "Responsible Business Decisions", discipline: "Business", units: 6, enrolled: 203 }
  ],
  assessments: [
    { id: "OPS-201-M1", course_id: "OPS-201", title: "Service health foundations", question_count: 3, due_at: "2026-11-15T23:59:00.000Z" },
    { id: "DATA-215-M1", course_id: "DATA-215", title: "Interpreting operational data", question_count: 3, due_at: "2026-11-18T23:59:00.000Z" },
    { id: "BUS-140-M1", course_id: "BUS-140", title: "Evidence-based decisions", question_count: 3, due_at: "2026-11-20T23:59:00.000Z" }
  ],
  questions: {
    "OPS-201-M1": [
      { id: 1, prompt: "Which signal most directly shows whether users can complete a request?", options: ["CPU model", "Success rate", "Resource group name", "Image tag"], answer_idx: 1 },
      { id: 2, prompt: "What should a health endpoint return when a required database is unavailable?", options: ["200", "204", "302", "503"], answer_idx: 3 },
      { id: 3, prompt: "Which practice reduces risk during a release?", options: ["Delete telemetry", "Skip validation", "Use a reversible rollout", "Share credentials"], answer_idx: 2 }
    ],
    "DATA-215-M1": [
      { id: 4, prompt: "Which percentile highlights slow requests without focusing on one outlier?", options: ["p50", "p95", "minimum", "count"], answer_idx: 1 },
      { id: 5, prompt: "What is the safest way to parameterize a database query?", options: ["String concatenation", "Prepared values", "Shell expansion", "URL encoding"], answer_idx: 1 },
      { id: 6, prompt: "A useful baseline should be collected when the service is?", options: ["Healthy", "Deleted", "Unreachable", "Unmonitored"], answer_idx: 0 }
    ],
    "BUS-140-M1": [
      { id: 7, prompt: "A durable operational decision should be supported by?", options: ["A single guess", "Measured evidence", "A hidden change", "An expired token"], answer_idx: 1 },
      { id: 8, prompt: "Which record explains why a production change was approved?", options: ["Change record", "Browser cache", "DNS suffix", "Process ID"], answer_idx: 0 },
      { id: 9, prompt: "What is a good first response to incomplete evidence?", options: ["Invent details", "Gather more evidence", "Delete logs", "Disable alerts"], answer_idx: 1 }
    ]
  }
};

function createPool() {
  return new Pool({
    host: process.env.POSTGRES_HOST,
    port: Number(process.env.POSTGRES_PORT || 5432),
    database: process.env.POSTGRES_DATABASE || "caldova",
    user: process.env.POSTGRES_USER,
    password: process.env.POSTGRES_PASSWORD,
    max: Number(process.env.POSTGRES_POOL_MAX || 10),
    connectionTimeoutMillis: Number(process.env.POSTGRES_CONNECT_TIMEOUT_MS || 5000),
    idleTimeoutMillis: 30000,
    ssl: (process.env.POSTGRES_SSL || "require") === "disable" ? false : { rejectUnauthorized: false }
  });
}

function createMemoryStore() {
  const attempts = [];
  return {
    mode: "memory",
    async health() {
      return { database: "memory", serverTime: new Date().toISOString() };
    },
    async summary() {
      return { courses: fixture.courses.length, learners: 4, assessments: fixture.assessments.length, attempts: attempts.length + 6 };
    },
    async courses() {
      return fixture.courses;
    },
    async course(id) {
      return fixture.courses.find((course) => course.id === id) || null;
    },
    async assessment(id) {
      return fixture.assessments.find((assessment) => assessment.id === id) || null;
    },
    async quiz(id) {
      const assessment = await this.assessment(id);
      if (!assessment) return null;
      return {
        ...assessment,
        questions: fixture.questions[id].map(({ answer_idx: _answer, ...question }) => question)
      };
    },
    async submit(id, learnerId, answers) {
      const questions = fixture.questions[id];
      if (!questions) return null;
      const correct = questions.reduce((count, question, index) => count + (question.answer_idx === answers[index] ? 1 : 0), 0);
      const scorePct = Math.round((correct / questions.length) * 100);
      const attempt = { id: attempts.length + 100, assessmentId: id, learnerId, total: questions.length, correct, scorePct, submittedAt: new Date().toISOString() };
      attempts.push(attempt);
      return attempt;
    },
    async grades(learnerId) {
      return {
        learnerId,
        records: [
          { courseId: "OPS-201", courseTitle: "Reliable Cloud Operations", attempts: 2, averageScore: 88, latestScore: 92 },
          { courseId: "DATA-215", courseTitle: "Applied Data Analysis", attempts: 1, averageScore: 84, latestScore: 84 }
        ]
      };
    },
    async exports() {
      return [{ id: 1, status: "completed", rowCount: 8, fileName: "caldova-grades-baseline.csv", completedAt: new Date().toISOString() }];
    },
    async close() {}
  };
}

function createPostgresStore() {
  const pool = createPool();
  pool.on("error", (error) => console.error(`db_pool_error message=${JSON.stringify(error.message)}`));

  return {
    mode: "postgres",
    async health() {
      const result = await pool.query("SELECT current_database() AS database, now() AS server_time");
      return { database: result.rows[0].database, serverTime: result.rows[0].server_time };
    },
    async summary() {
      const result = await pool.query(`
        SELECT
          (SELECT count(*)::int FROM courses) AS courses,
          (SELECT count(*)::int FROM learners) AS learners,
          (SELECT count(*)::int FROM assessments) AS assessments,
          (SELECT count(*)::int FROM quiz_attempts) AS attempts
      `);
      return result.rows[0];
    },
    async courses() {
      const result = await pool.query("SELECT id, title, discipline, units, enrolled FROM courses ORDER BY id");
      return result.rows;
    },
    async course(id) {
      const result = await pool.query("SELECT id, title, discipline, units, enrolled FROM courses WHERE id = $1", [id]);
      return result.rows[0] || null;
    },
    async assessment(id) {
      const result = await pool.query(
        `SELECT a.id, a.course_id, a.title, a.due_at, count(q.id)::int AS question_count
         FROM assessments a
         LEFT JOIN quiz_questions q ON q.assessment_id = a.id
         WHERE a.id = $1
         GROUP BY a.id`,
        [id]
      );
      return result.rows[0] || null;
    },
    async quiz(id) {
      // CALDOVA-PERF-INJECT-POINT: later regression scenarios add expensive work below this anchor.
      const client = await pool.connect();
      let bank;
      let result;
      try {
        await withConnectionHold(client, Number(process.env.CALDOVA_DB_HOLD_MS || 0));
        bank = await runQuestionBankLookup(client, id);
        result = await client.query(
          `SELECT a.id, a.course_id, a.title, a.due_at,
                  q.id AS question_id, q.prompt, q.options
           FROM assessments a
           JOIN quiz_questions q ON q.assessment_id = a.id
           WHERE a.id = $1
           ORDER BY q.position`,
          [id]
        );
      } finally {
        client.release();
      }
      if (result.rows.length === 0) return null;
      return {
        id: result.rows[0].id,
        course_id: result.rows[0].course_id,
        title: result.rows[0].title,
        due_at: result.rows[0].due_at,
        available: bank.rows[0].available,
        question_count: result.rows.length,
        questions: result.rows.map((row) => ({ id: row.question_id, prompt: row.prompt, options: row.options }))
      };
    },
    async submit(id, learnerId, answers) {
      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        const key = await client.query(
          "SELECT answer_idx FROM quiz_questions WHERE assessment_id = $1 ORDER BY position",
          [id]
        );
        if (key.rows.length === 0) {
          await client.query("ROLLBACK");
          return null;
        }
        const correct = key.rows.reduce((count, row, index) => count + (row.answer_idx === answers[index] ? 1 : 0), 0);
        const scorePct = Math.round((correct / key.rows.length) * 100);
        const result = await client.query(
          `INSERT INTO quiz_attempts (assessment_id, learner_id, total, correct, score_pct)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id, assessment_id, learner_id, total, correct, score_pct, submitted_at`,
          [id, learnerId, key.rows.length, correct, scorePct]
        );
        await client.query("COMMIT");
        return result.rows[0];
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      } finally {
        client.release();
      }
    },
    async grades(learnerId) {
      const result = await pool.query(
        `SELECT c.id AS course_id, c.title AS course_title, count(qa.id)::int AS attempts,
                round(avg(qa.score_pct))::int AS average_score,
                (array_agg(qa.score_pct ORDER BY qa.submitted_at DESC))[1]::int AS latest_score
         FROM quiz_attempts qa
         JOIN assessments a ON a.id = qa.assessment_id
         JOIN courses c ON c.id = a.course_id
         WHERE qa.learner_id = $1
         GROUP BY c.id, c.title
         ORDER BY c.id`,
        [learnerId]
      );
      return { learnerId, records: result.rows };
    },
    async exports() {
      const result = await pool.query(
        `SELECT id, status, row_count, file_name, completed_at
         FROM reporting_exports
         ORDER BY completed_at DESC NULLS LAST, id DESC
         LIMIT 10`
      );
      return result.rows;
    },
    async close() {
      await pool.end();
    }
  };
}

function createStore() {
  return process.env.CALDOVA_DATA_MODE === "memory" ? createMemoryStore() : createPostgresStore();
}

module.exports = { createPool, createStore };
