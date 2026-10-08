"use strict";

const fs = require("node:fs");
const path = require("node:path");

const catalogPath = path.join(__dirname, "..", "scenarios.json");

function loadCatalog() {
  const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
  if (catalog.schemaVersion !== 1 || !Array.isArray(catalog.scenarios) || catalog.scenarios.length === 0) {
    throw new Error("Simulator scenario catalog is empty or uses an unsupported schema.");
  }
  return catalog;
}

function getScenario(id) {
  const scenario = loadCatalog().scenarios.find((entry) => entry.id === id);
  if (!scenario) throw new Error(`Unknown scenario '${id}'. Refresh the simulator and select an available scenario.`);
  return scenario;
}

module.exports = { loadCatalog, getScenario, catalogPath };
