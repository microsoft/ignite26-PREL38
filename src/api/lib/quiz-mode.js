"use strict";

const AVAILABLE = "available";
const UNAVAILABLE = "unavailable";

function getQuizMode(value = process.env.CALDOVA_QUIZ_MODE) {
  return String(value || AVAILABLE).trim().toLowerCase() === UNAVAILABLE
    ? UNAVAILABLE
    : AVAILABLE;
}

function getQuizAvailability(value) {
  const mode = getQuizMode(value);
  return mode === AVAILABLE
    ? { available: true, mode }
    : {
        available: false,
        mode,
        statusCode: 503,
        body: {
          error: "quiz_temporarily_unavailable",
          detail: "Quiz activities are temporarily unavailable. Course content remains available."
        }
      };
}

module.exports = { getQuizAvailability, getQuizMode };
