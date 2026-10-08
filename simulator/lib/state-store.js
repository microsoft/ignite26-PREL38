"use strict";

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const DEFAULT_STALE_LOCK_MS = 15 * 60 * 1000;

const transitions = {
  idle: new Set(["checking", "resetting", "error"]),
  ready: new Set(["checking", "injecting", "resetting", "error"]),
  checking: new Set(["ready", "error", "cancelled"]),
  injecting: new Set(["waiting_alert", "error", "cancelled"]),
  waiting_alert: new Set(["investigating", "error", "cancelled"]),
  investigating: new Set(["checking_recovery", "resetting"]),
  checking_recovery: new Set(["recovered", "investigating", "error", "cancelled"]),
  recovered: new Set(["checking_recovery", "resetting"]),
  resetting: new Set(["idle", "error", "cancelled"]),
  error: new Set(["checking", "resetting"]),
  cancelled: new Set(["checking", "resetting"])
};

function defaultState(learnerNumber) {
  return {
    schemaVersion: 1,
    learnerNumber,
    status: "idle",
    phase: "Waiting for configuration check",
    progress: 0,
    ready: false,
    active: false,
    targetAgent: null,
    scenarioId: null,
    investigationUrl: null,
    error: null,
    result: null,
    updatedAt: new Date().toISOString()
  };
}

class StateStore {
  constructor(directory, options = {}) {
    this.directory = directory;
    this.staleLockMs = options.staleLockMs || DEFAULT_STALE_LOCK_MS;
    this.isProcessAlive = options.isProcessAlive || ((pid) => {
      try {
        process.kill(pid, 0);
        return true;
      } catch (error) {
        return error.code === "EPERM";
      }
    });
    fs.mkdirSync(directory, { recursive: true });
  }

  statePath(learnerNumber) {
    return path.join(this.directory, `simulator-state-user${learnerNumber}.json`);
  }

  lockPath(learnerNumber) {
    return path.join(this.directory, `simulator-lock-user${learnerNumber}.json`);
  }

  read(learnerNumber) {
    const file = this.statePath(learnerNumber);
    if (!fs.existsSync(file)) return defaultState(learnerNumber);
    return JSON.parse(fs.readFileSync(file, "utf8"));
  }

  write(state) {
    const next = { ...state, updatedAt: new Date().toISOString() };
    const file = this.statePath(next.learnerNumber);
    const temp = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(temp, JSON.stringify(next, null, 2));
    fs.renameSync(temp, file);
    return next;
  }

  transition(learnerNumber, nextStatus, patch = {}) {
    const current = this.read(learnerNumber);
    if (current.status !== nextStatus && !transitions[current.status]?.has(nextStatus)) {
      throw new Error(`Invalid simulator transition '${current.status}' → '${nextStatus}'. Reset the scenario if the previous action was interrupted.`);
    }
    return this.write({ ...current, ...patch, status: nextStatus });
  }

  acquire(learnerNumber, action) {
    const file = this.lockPath(learnerNumber);
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const token = crypto.randomUUID();
      try {
        const descriptor = fs.openSync(file, "wx", 0o600);
        try {
          fs.writeFileSync(descriptor, JSON.stringify({
            schemaVersion: 1,
            learnerNumber,
            action,
            pid: process.pid,
            token,
            acquiredAt: new Date().toISOString()
          }));
        } finally {
          fs.closeSync(descriptor);
        }
        return () => {
          try {
            const current = JSON.parse(fs.readFileSync(file, "utf8"));
            if (current.pid === process.pid && current.token === token) {
              fs.rmSync(file);
            }
          } catch (error) {
            if (error.code !== "ENOENT") throw error;
          }
        };
      } catch (error) {
        if (error.code !== "EEXIST") throw error;
        const inspection = this.inspectLock(file);
        if (inspection.recoverable) {
          fs.rmSync(file);
          continue;
        }
        throw new Error(inspection.message);
      }
    }
    throw new Error(`Could not safely recover the operation lock for learner ${learnerNumber}. Remove it only after confirming its owner process is no longer running: ${file}`);
  }

  inspectLock(file) {
    const stat = fs.statSync(file);
    const ageMs = Math.max(0, Date.now() - stat.mtimeMs);
    let lock;
    try {
      lock = JSON.parse(fs.readFileSync(file, "utf8"));
    } catch {
      if (ageMs >= this.staleLockMs) {
        return { recoverable: true, message: "Expired malformed lock." };
      }
      return {
        recoverable: false,
        message: `The simulator lock '${file}' is malformed but only ${Math.round(ageMs / 1000)} seconds old. Wait ${Math.ceil((this.staleLockMs - ageMs) / 1000)} seconds, then retry; do not delete a lock that may still belong to a live operation.`
      };
    }

    const validPid = Number.isInteger(lock.pid) && lock.pid > 0;
    const acquiredAtMs = Date.parse(lock.acquiredAt);
    const validAge = Number.isFinite(acquiredAtMs) && acquiredAtMs <= Date.now() + 60_000;
    const alive = validPid && this.isProcessAlive(lock.pid);
    if (alive) {
      return {
        recoverable: false,
        message: `Another '${lock.action || "unknown"}' operation already owns learner ${lock.learnerNumber ?? "unknown"} in live process ${lock.pid} (started ${lock.acquiredAt || "at an unknown time"}). Wait for it to finish or use Cancel before retrying.`
      };
    }
    if (validPid && validAge) {
      return { recoverable: true, message: `Recovered dead process ${lock.pid}.` };
    }
    if (ageMs >= this.staleLockMs) {
      return { recoverable: true, message: "Recovered expired malformed lock metadata." };
    }
    return {
      recoverable: false,
      message: `The simulator lock '${file}' has invalid owner metadata and is only ${Math.round(ageMs / 1000)} seconds old. Wait for the ${Math.ceil(this.staleLockMs / 1000)}-second safety window or confirm the owner process is stopped before retrying.`
    };
  }

  clear(learnerNumber) {
    fs.rmSync(this.statePath(learnerNumber), { force: true });
    const lock = this.lockPath(learnerNumber);
    if (!fs.existsSync(lock)) return;
    const inspection = this.inspectLock(lock);
    if (!inspection.recoverable) {
      throw new Error(`Simulator state was cleared, but the operation lock was preserved. ${inspection.message}`);
    }
    fs.rmSync(lock);
  }
}

module.exports = { StateStore, defaultState, transitions, DEFAULT_STALE_LOCK_MS };
