"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const projectId = "saintfrancisschedule";
const databaseName = "(default)";
const explicitGuard = "saintfrancisschedule";
const firebaseToolsRoot = "/opt/homebrew/lib/node_modules/firebase-tools/lib";
const firestoreBase =
  `https://firestore.googleapis.com/v1/projects/${projectId}/` +
  `databases/${databaseName}`;

function requireExplicitProductionGuard() {
  if (process.env.ALLOW_PRODUCTION_ACCOUNT_DELETION_CANARY !== explicitGuard) {
    throw new Error(
      "Refusing production canary without the exact explicit guard",
    );
  }
  if (process.env.FIRESTORE_EMULATOR_HOST ||
      process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error("Production canary cannot run against emulators");
  }
}

function firebaseAPIKey() {
  const plistPath = path.resolve(
    __dirname,
    "../../Schedule/GoogleService-Info.plist",
  );
  const plist = fs.readFileSync(plistPath, "utf8");
  const match = plist.match(
    /<key>API_KEY<\/key>\s*<string>([^<]+)<\/string>/,
  );
  if (!match) {
    throw new Error("Firebase API key is missing from GoogleService-Info.plist");
  }
  return match[1];
}

async function cliAccessToken() {
  const cliAuth = require(`${firebaseToolsRoot}/auth`);
  const account = cliAuth.getProjectDefaultAccount(
    path.resolve(__dirname, "../.."),
  );
  if (!account?.tokens?.refresh_token) {
    throw new Error("Firebase CLI is not signed in");
  }
  const token = await cliAuth.getAccessToken(
    account.tokens.refresh_token,
    ["https://www.googleapis.com/auth/cloud-platform"],
  );
  if (typeof token.access_token !== "string") {
    throw new Error("Firebase CLI access token is unavailable");
  }
  return token.access_token;
}

async function identityRequest(action, apiKey, body) {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:${action}` +
      `?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify(body),
    },
  );
  return {response, body: await response.json()};
}

async function createDisposableUser(email, password, apiKey) {
  const result = await identityRequest("signUp", apiKey, {
    email,
    password,
    returnSecureToken: true,
  });
  if (!result.response.ok ||
      typeof result.body.localId !== "string" ||
      typeof result.body.idToken !== "string") {
    throw new Error(
      `Disposable Auth creation failed with HTTP ${result.response.status}`,
    );
  }
  return result.body;
}

async function signIn(email, password, apiKey) {
  const result = await identityRequest("signInWithPassword", apiKey, {
    email,
    password,
    returnSecureToken: true,
  });
  if (!result.response.ok || typeof result.body.idToken !== "string") {
    throw new Error(`Disposable sign-in failed with HTTP ${result.response.status}`);
  }
  return result.body.idToken;
}

function documentName(relativePath) {
  return `projects/${projectId}/databases/${databaseName}/documents/` +
    relativePath;
}

function documentWrite(relativePath, fields) {
  return {update: {name: documentName(relativePath), fields}};
}

function deleteWrite(relativePath) {
  return {delete: documentName(relativePath)};
}

function stringValue(value) {
  return {stringValue: value};
}

function integerValue(value) {
  return {integerValue: String(value)};
}

function booleanValue(value) {
  return {booleanValue: value};
}

function timestampValue(date = new Date()) {
  return {timestampValue: date.toISOString()};
}

async function firestoreRequest(pathSuffix, accessToken, options = {}) {
  const response = await fetch(`${firestoreBase}${pathSuffix}`, {
    ...options,
    headers: {
      authorization: `Bearer ${accessToken}`,
      ...(options.body ? {"content-type": "application/json"} : {}),
      ...(options.headers ?? {}),
    },
  });
  const text = await response.text();
  let body = {};
  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = {raw: text.slice(0, 300)};
    }
  }
  return {response, body};
}

async function commitAdmin(accessToken, writes) {
  const result = await firestoreRequest("/documents:commit", accessToken, {
    method: "POST",
    body: JSON.stringify({writes}),
  });
  if (!result.response.ok) {
    throw new Error(`Admin commit failed with HTTP ${result.response.status}`);
  }
}

async function seedFixture(userId, email, accessToken) {
  const now = new Date();
  const paths = [];
  const writes = [];
  const add = (relativePath, fields) => {
    paths.push(relativePath);
    writes.push(documentWrite(relativePath, fields));
  };

  add(`users/${userId}`, {
    email: stringValue(email),
    private: booleanValue(true),
    canary: booleanValue(true),
  });
  add(`users/${userId}/sessions/session`, {
    startedAt: timestampValue(now),
    canary: booleanValue(true),
  });
  add(`users/${userId}/sync/state/sessions/legacy-session`, {
    startedAt: timestampValue(now),
    canary: booleanValue(true),
  });
  add(`users/${userId}/futureSchema/branch/deeper/record`, {
    mustBeDeleted: booleanValue(true),
    canary: booleanValue(true),
  });
  for (let index = 0; index < 525; index += 1) {
    add(
      `users/${userId}/sessions/bulk-${String(index).padStart(3, "0")}`,
      {
        startedAt: timestampValue(now),
        index: integerValue(index),
        canary: booleanValue(true),
      },
    );
  }

  for (let offset = 0; offset < writes.length; offset += 400) {
    await commitAdmin(accessToken, writes.slice(offset, offset + 400));
  }
  return paths;
}

function deletionCommit(userId) {
  const rootName = documentName(`users/${userId}`);
  const requestName = documentName(`accountDeletionRequests/${userId}`);
  const markerFields = {
    state: {stringValue: "requested"},
    workflowVersion: {integerValue: "1"},
  };
  return {
    writes: [
      {
        update: {
          name: rootName,
          fields: {
            accountDeletion: {mapValue: {fields: markerFields}},
          },
        },
        updateMask: {fieldPaths: ["accountDeletion"]},
        updateTransforms: [{
          fieldPath: "accountDeletion.requestedAt",
          setToServerValue: "REQUEST_TIME",
        }],
        currentDocument: {exists: true},
      },
      {
        update: {name: requestName, fields: markerFields},
        updateTransforms: [{
          fieldPath: "requestedAt",
          setToServerValue: "REQUEST_TIME",
        }],
        currentDocument: {exists: false},
      },
    ],
  };
}

async function requestDeletionThroughRules(userId, idToken) {
  const response = await fetch(`${firestoreBase}/documents:commit`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${idToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(deletionCommit(userId)),
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(
      `Deletion request was rejected with HTTP ${response.status}: ` +
      body.slice(0, 300),
    );
  }
}

async function getDocument(relativePath, accessToken) {
  const result = await firestoreRequest(
    `/documents/${relativePath}`,
    accessToken,
  );
  if (result.response.status === 404) {
    return null;
  }
  if (!result.response.ok) {
    throw new Error(
      `Document read failed with HTTP ${result.response.status}`,
    );
  }
  return result.body;
}

async function waitForCompletion(userId, accessToken) {
  const deadline = Date.now() + 5 * 60_000;
  let lastState = "missing";
  while (Date.now() < deadline) {
    const document = await getDocument(
      `accountDeletionRequests/${userId}`,
      accessToken,
    );
    lastState = document?.fields?.state?.stringValue ?? "missing";
    if (lastState === "completed") {
      return document;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`Timed out waiting for deletion; final state=${lastState}`);
}

async function assertAuthDeleted(email, password, apiKey) {
  const result = await identityRequest("signInWithPassword", apiKey, {
    email,
    password,
    returnSecureToken: true,
  });
  assert.equal(result.response.ok, false, "deleted Auth user must not sign in");
}

async function assertClientIsFenced(userId, idToken) {
  const response = await fetch(
    `${firestoreBase}/documents/users/${userId}`,
    {headers: {authorization: `Bearer ${idToken}`}},
  );
  assert.equal(response.status, 403, "cached client token must remain fenced");
}

async function assertNoUserCollections(userId, accessToken) {
  const result = await firestoreRequest(
    `/documents/users/${userId}:listCollectionIds`,
    accessToken,
    {method: "POST", body: JSON.stringify({pageSize: 100})},
  );
  if (!result.response.ok) {
    throw new Error(
      `Collection-list verification failed with HTTP ${result.response.status}`,
    );
  }
  assert.deepEqual(result.body.collectionIds ?? [], []);
}

async function deleteAuthAdmin(userId, accessToken) {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${projectId}/` +
      "accounts:delete",
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({localId: userId}),
    },
  );
  if (!response.ok && response.status !== 404) {
    throw new Error(`Auth cleanup failed with HTTP ${response.status}`);
  }
}

async function bestEffortCleanup(userId, seededPaths, accessToken) {
  const paths = [
    ...seededPaths.filter((item) => item !== `users/${userId}`),
    `accountDeletionRequests/${userId}`,
    `users/${userId}`,
  ];
  for (let offset = 0; offset < paths.length; offset += 400) {
    await commitAdmin(
      accessToken,
      paths.slice(offset, offset + 400).map(deleteWrite),
    ).catch(() => undefined);
  }
  await deleteAuthAdmin(userId, accessToken).catch(() => undefined);
}

async function main() {
  requireExplicitProductionGuard();
  const apiKey = firebaseAPIKey();
  const accessToken = await cliAccessToken();
  const suffix = crypto.randomBytes(12).toString("hex");
  const email = `codex-deletion-canary-${suffix}@example.invalid`;
  const password = crypto.randomBytes(24).toString("base64url");
  let userId;
  let idToken;
  let requestAccepted = false;
  let seededPaths = [];

  try {
    const created = await createDisposableUser(email, password, apiKey);
    userId = created.localId;
    idToken = created.idToken;
    seededPaths = await seedFixture(userId, email, accessToken);
    idToken = await signIn(email, password, apiKey);
    await requestDeletionThroughRules(userId, idToken);
    requestAccepted = true;
    const completedRequest = await waitForCompletion(userId, accessToken);

    assert.equal(completedRequest.fields.state.stringValue, "completed");
    assert.equal(completedRequest.fields.workflowVersion.integerValue, "1");
    assert.ok(completedRequest.fields.authDeletedAt.timestampValue);
    assert.ok(completedRequest.fields.completedAt.timestampValue);
    await assertAuthDeleted(email, password, apiKey);
    assert.equal(
      await getDocument(`users/${userId}/sessions/session`, accessToken),
      null,
    );
    assert.equal(
      await getDocument(
        `users/${userId}/sync/state/sessions/legacy-session`,
        accessToken,
      ),
      null,
    );
    assert.equal(
      await getDocument(
        `users/${userId}/futureSchema/branch/deeper/record`,
        accessToken,
      ),
      null,
    );
    assert.equal(
      await getDocument(`users/${userId}/sessions/bulk-000`, accessToken),
      null,
    );
    assert.equal(
      await getDocument(`users/${userId}/sessions/bulk-524`, accessToken),
      null,
    );
    await assertNoUserCollections(userId, accessToken);

    const root = await getDocument(`users/${userId}`, accessToken);
    assert.deepEqual(Object.keys(root.fields), ["accountDeletion"]);
    const marker = root.fields.accountDeletion.mapValue.fields;
    assert.equal(marker.state.stringValue, "completed");
    assert.equal(marker.workflowVersion.integerValue, "1");
    assert.ok(marker.authDeletedAt.timestampValue);
    assert.ok(marker.completedAt.timestampValue);
    await assertClientIsFenced(userId, idToken);

    console.log(JSON.stringify({
      result: "passed",
      seededSessionDocuments: 526,
      legacyNestedDocumentDeleted: true,
      unknownNestedDocumentDeleted: true,
      authUserDeleted: true,
      cachedClientTokenFenced: true,
      completedFenceRetained: true,
    }));
  } catch (error) {
    if (userId && !requestAccepted) {
      await bestEffortCleanup(userId, seededPaths, accessToken);
    }
    throw error;
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
