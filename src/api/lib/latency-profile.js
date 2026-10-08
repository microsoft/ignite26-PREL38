"use strict";

module.exports = {
  name: "healthy",
  delayMs: 0,
  appliesTo(path) {
    return /^\/(?:quiz|assessments)\//.test(path);
  },
  async beforeRequest() {}
};
