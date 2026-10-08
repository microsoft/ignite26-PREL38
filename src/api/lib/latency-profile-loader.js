"use strict";

function loadLatencyProfile() {
  if (process.env.NODE_ENV === "test" && process.env.CALDOVA_TEST_LATENCY_PROFILE === "bad") {
    return require("../variants/latency-profile.bad");
  }
  return require("./latency-profile");
}

module.exports = { loadLatencyProfile };
