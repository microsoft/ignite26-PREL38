"use strict";

const FEATURE = "course_recommendations";
const AVAILABLE = "available";
const UNAVAILABLE = "unavailable";

function getRecommendationsMode(value = process.env.CALDOVA_RECOMMENDATIONS_MODE) {
  return String(value || UNAVAILABLE).trim().toLowerCase() === AVAILABLE
    ? AVAILABLE
    : UNAVAILABLE;
}

function getRecommendationsHealth(value) {
  const mode = getRecommendationsMode(value);
  const available = mode === AVAILABLE;
  return {
    statusCode: available ? 200 : 503,
    body: {
      status: available ? AVAILABLE : "degraded",
      feature: FEATURE,
      message: available
        ? "Course recommendations are available."
        : "Course recommendations are temporarily unavailable. Courses and assessments remain available.",
      timestamp: new Date().toISOString()
    }
  };
}

module.exports = {
  FEATURE,
  AVAILABLE,
  UNAVAILABLE,
  getRecommendationsMode,
  getRecommendationsHealth
};
