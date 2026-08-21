# Account deletion worker

`processAccountDeletion` is the server-owned deletion path. It uses
`/accountDeletionRequests/{uid}` as the durable job and mirrors its state into
`/users/{uid}.accountDeletion` as the security-rules fence.

1. After Firebase reauthentication and a forced ID-token refresh, the client
   uses one Firestore transaction or write batch to merge the marker into the
   user root and create the request document with the same marker:

   ```text
   /users/{uid}.accountDeletion = {
     state: "requested",
     requestedAt: server timestamp,
     workflowVersion: 1
   }

   /accountDeletionRequests/{uid} = {
     state: "requested",
     requestedAt: the same server timestamp,
     workflowVersion: 1
   }
   ```

2. Firestore rules require `auth_time` to be no more than five minutes old and
   require both documents in the same atomic commit. The embedded root marker
   immediately rejects every further client read or write for the UID. Root
   deletion, arbitrary session deletion, and legacy sync-document deletion are
   denied, so Firestore-first deletion in older app versions fails safely.
3. The retry-enabled function deletes the Firebase Auth user first, atomically
   checkpoints both documents as `auth_deleted`, recursively removes every
   subcollection below the user, and atomically writes both `completed`
   markers. The root is retained as a minimal tombstone.
4. An hourly scheduled sweep finds `requested` or `auth_deleted` request jobs
   and resumes them after the Firestore event retry window has ended.

The trigger watches only `accountDeletionRequests`; normal user-root saves do
not invoke a function. Normal user-data rules consult the root they already
need and do not add a request-collection lookup.

All operations are idempotent. A crash after Auth deletion sees
`auth/user-not-found` and continues. A crash during recursive deletion repeats
the remaining cleanup. Concurrent workers never regress the job state. The
retained request and root tombstones fence cached ID tokens and prevent
accidental data recreation if the UID is reused.

If a request retry sees an existing request document, it should treat the
request as accepted instead of trying to update the server-owned job.

## Deployment order

1. Deploy `firestore.rules` first. Existing app builds will be unable to finish
   account deletion, but cannot enter the old partial-data-loss sequence.
2. Deploy `processAccountDeletion` and `sweepAccountDeletions`. Verify their
   service account can delete Firebase Auth users and Firestore documents.
   Cloud Scheduler and its required billing/API setup must be enabled.
3. Release a client that, after every supported reauthentication method, forces
   an ID-token refresh and atomically writes both request markers instead of
   deleting cloud documents or calling `FirebaseAuth.User.delete()` itself.

Do not enable TTL on either completed tombstone unless it is acceptable for an
old cached client or deliberately reused UID to recreate user data. Any future
Admin SDK writer must explicitly check the root tombstone because Admin SDK
traffic bypasses Firestore rules.

## Production prerequisites

- Use the Blaze plan and enable Cloud Functions, Eventarc, Pub/Sub, Cloud
  Scheduler, Cloud Build, Artifact Registry, Firestore, and Firebase Auth APIs.
- Run both functions in the deployed Firestore database's region. The source
  currently uses the Firebase default (`us-central1`) because this repository
  does not record the production database location; verify that location before
  deployment and set the `region` option on both exports if it differs.
- Give the selected runtime service account Firestore data read/write/delete
  access and Firebase Auth user get/delete access. A least-privilege custom role
  is preferable; `roles/datastore.user` plus `roles/firebaseauth.admin` is the
  broader built-in-role combination. The deployer must be able to act as that
  service account.
- Keep Node 22 available for deployment. Dependencies and the lockfile are
  pinned; `npm audit --omit=dev` currently reports zero vulnerabilities.
- Commit `.firebaserc`, `firebase.json`, `firestore.rules`, and this `functions`
  directory. They were not part of the repository's tracked baseline.

## Local verification

Run the pure state-machine tests with `npm test`. From the repository root, run
the end-to-end Auth/Firestore/Functions emulator test with:

```sh
firebase emulators:exec --only auth,firestore,functions \
  "npm --prefix functions run test:emulator"
```

The integration test refuses to run unless both Admin SDK endpoints are local.
