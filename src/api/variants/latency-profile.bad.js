"use strict";

const delayMs = 1250;

module.exports = {
  name: "elevated-response-time",
  delayMs,
  appliesTo(path) {
    return /^\/(?:quiz|assessments)\//.test(path);
  },
  beforeRequest() {
    return new Promise((resolve) => setTimeout(resolve, delayMs));
  }
};
