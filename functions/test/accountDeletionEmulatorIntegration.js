"use strict";

const assert = require("node:assert/strict");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {Timestamp, getFirestore} = require("firebase-admin/firestore");

function requireLocalEmulator(variable) {
  const value = process.env[variable];
  if (value === undefined ||
      (!value.startsWith("127.0.0.1:") && !value.startsWith("localhost:"))) {
    throw new Error(`${variable} must target a local emulator`);
  }
}

async function waitForCompleted(reference) {
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    const snapshot = await reference.get();
    if (snapshot.data()?.state === "completed") {
      return snapshot.data();
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error("Timed out waiting for the deletion worker");
}

async function main() {
  requireLocalEmulator("FIRESTORE_EMULATOR_HOST");
  requireLocalEmulator("FIREBASE_AUTH_EMULATOR_HOST");

  const projectId = process.env.GCLOUD_PROJECT ?? "saintfrancisschedule";
  initializeApp({projectId});
  const auth = getAuth();
  const database = getFirestore();
  const userId = "backend-deletion-integration-user";
  const userReference = database.doc(`users/${userId}`);
  const requestReference = database.doc(`accountDeletionRequests/${userId}`);
  const sessionReference = userReference.collection("sessions").doc("session");
  const legacySessionReference = userReference
    .collection("sync")
    .doc("state")
    .collection("sessions")
    .doc("legacy-session");
  const futureReference = userReference
    .collection("futureSchema")
    .doc("branch")
    .collection("deeper")
    .doc("record");

  await auth.createUser({uid: userId, email: "delete-fixture@example.test"});
  await userReference.set({email: "delete-fixture@example.test", private: true});
  await sessionReference.set({startedAt: Timestamp.now()});
  await legacySessionReference.set({startedAt: Timestamp.now()});
  await futureReference.set({mustBeDeleted: true});

  // Cross the client's historical 400/500-write chunk boundaries so the
  // server test proves recursive deletion is not limited to enumerated pages.
  const bulkSessionReferences = [];
  for (let offset = 0; offset < 525; offset += 400) {
    const seedBatch = database.batch();
    for (let index = offset; index < Math.min(offset + 400, 525); index += 1) {
      const reference = userReference
        .collection("sessions")
        .doc(`bulk-${String(index).padStart(3, "0")}`);
      bulkSessionReferences.push(reference);
      seedBatch.set(reference, {startedAt: Timestamp.now(), index});
    }
    await seedBatch.commit();
  }

  const requestedAt = Timestamp.now();
  const requestedMarker = {
    state: "requested",
    requestedAt,
    workflowVersion: 1,
  };
  const requestBatch = database.batch();
  requestBatch.update(userReference, {accountDeletion: requestedMarker});
  requestBatch.create(requestReference, requestedMarker);
  await requestBatch.commit();

  const completedRequest = await waitForCompleted(requestReference);
  assert.equal(completedRequest.state, "completed");
  assert.ok(completedRequest.authDeletedAt instanceof Timestamp);
  assert.ok(completedRequest.completedAt instanceof Timestamp);

  await assert.rejects(
    auth.getUser(userId),
    (error) => error?.code === "auth/user-not-found",
  );
  assert.equal((await sessionReference.get()).exists, false);
  assert.equal((await legacySessionReference.get()).exists, false);
  assert.equal((await futureReference.get()).exists, false);
  assert.equal((await bulkSessionReferences[0].get()).exists, false);
  assert.equal((await bulkSessionReferences.at(-1).get()).exists, false);
  assert.equal((await userReference.collection("sessions").get()).empty, true);
  assert.deepEqual(await userReference.listCollections(), []);

  const rootData = (await userReference.get()).data();
  assert.deepEqual(Object.keys(rootData), ["accountDeletion"]);
  assert.equal(rootData.accountDeletion.state, "completed");
  assert.equal(rootData.accountDeletion.workflowVersion, 1);
  assert.ok(rootData.accountDeletion.authDeletedAt instanceof Timestamp);
  assert.ok(rootData.accountDeletion.completedAt instanceof Timestamp);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
