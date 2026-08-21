"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  runAccountDeletion,
} = require("../lib/accountDeletionWorkflow.js");

const requested = () => ({
  state: "requested",
  workflowVersion: 1,
  requestedAt: "request-time",
});

class FakeBackend {
  constructor(marker) {
    this.marker = marker;
    this.events = [];
    this.authError = undefined;
    this.recursiveFailuresRemaining = 0;
    this.completeDuringCheckpoint = false;
  }

  async readMarker() {
    this.events.push("read");
    return this.marker;
  }

  async deleteAuthUser() {
    this.events.push("delete_auth");
    if (this.authError !== undefined) {
      throw this.authError;
    }
  }

  async checkpointAuthDeletedAndStripRoot(_userId, marker) {
    this.events.push("checkpoint_request_and_strip_root");
    if (this.completeDuringCheckpoint) {
      this.marker = {...marker, state: "completed"};
      return this.marker;
    }
    this.marker = {
      ...marker,
      state: "auth_deleted",
      authDeletedAt: "auth-delete-time",
    };
    return this.marker;
  }

  async deleteUserSubcollections() {
    this.events.push("delete_subcollections");
    if (this.recursiveFailuresRemaining > 0) {
      this.recursiveFailuresRemaining -= 1;
      throw new Error("partial recursive delete failure");
    }
  }

  async markRequestAndRootCompleted() {
    this.events.push("complete");
    this.marker = {...this.marker, state: "completed"};
  }

  isMissingAuthUser(error) {
    return error?.code === "auth/user-not-found";
  }
}

test("deletes Auth before stripping root or deleting subcollections", async () => {
  const backend = new FakeBackend(requested());

  await runAccountDeletion("user-1", backend);

  assert.deepEqual(backend.events, [
    "read",
    "delete_auth",
    "checkpoint_request_and_strip_root",
    "delete_subcollections",
    "complete",
  ]);
  assert.equal(backend.marker.state, "completed");
});

test("an Auth failure cannot delete any Firestore data", async () => {
  const backend = new FakeBackend(requested());
  backend.authError = new Error("Auth unavailable");

  await assert.rejects(
    runAccountDeletion("user-1", backend),
    /Auth unavailable/,
  );

  assert.deepEqual(backend.events, ["read", "delete_auth"]);
  assert.equal(backend.marker.state, "requested");
});

test("auth/user-not-found resumes a prior successful Auth deletion", async () => {
  const backend = new FakeBackend(requested());
  backend.authError = {code: "auth/user-not-found"};

  await runAccountDeletion("user-1", backend);

  assert.deepEqual(backend.events, [
    "read",
    "delete_auth",
    "checkpoint_request_and_strip_root",
    "delete_subcollections",
    "complete",
  ]);
  assert.equal(backend.marker.state, "completed");
});

test("a partial recursive failure retries from auth_deleted", async () => {
  const backend = new FakeBackend({
    ...requested(),
    state: "auth_deleted",
    authDeletedAt: "auth-delete-time",
  });
  backend.recursiveFailuresRemaining = 1;

  await assert.rejects(
    runAccountDeletion("user-1", backend),
    /partial recursive delete failure/,
  );
  assert.equal(backend.marker.state, "auth_deleted");

  await runAccountDeletion("user-1", backend);

  assert.deepEqual(backend.events, [
    "read",
    "delete_subcollections",
    "read",
    "delete_subcollections",
    "complete",
  ]);
  assert.equal(backend.marker.state, "completed");
});

test("a completed marker is a no-op", async () => {
  const backend = new FakeBackend({
    ...requested(),
    state: "completed",
    authDeletedAt: "auth-delete-time",
  });

  await runAccountDeletion("user-1", backend);

  assert.deepEqual(backend.events, ["read"]);
});

test("a concurrent completion is never regressed", async () => {
  const backend = new FakeBackend(requested());
  backend.completeDuringCheckpoint = true;

  await runAccountDeletion("user-1", backend);

  assert.deepEqual(backend.events, [
    "read",
    "delete_auth",
    "checkpoint_request_and_strip_root",
  ]);
  assert.equal(backend.marker.state, "completed");
});
