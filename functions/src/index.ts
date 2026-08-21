import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  AccountDeletionBackend,
  DeletionMarker,
  runAccountDeletion,
} from "./accountDeletionWorkflow";

initializeApp();

const WORKFLOW_VERSION = 1;

function deletionMarkerFrom(data: FirebaseFirestore.DocumentData | undefined):
  DeletionMarker | undefined {
  const marker = data as Record<string, unknown> | undefined;
  if (marker === undefined || marker.workflowVersion !== WORKFLOW_VERSION) {
    return undefined;
  }
  if (
    marker.state !== "requested" &&
    marker.state !== "auth_deleted" &&
    marker.state !== "completed"
  ) {
    return undefined;
  }
  if (!(marker.requestedAt instanceof Timestamp)) {
    return undefined;
  }
  if (
    marker.state !== "requested" &&
    !(marker.authDeletedAt instanceof Timestamp)
  ) {
    return undefined;
  }
  if (
    marker.state === "completed" &&
    !(marker.completedAt instanceof Timestamp)
  ) {
    return undefined;
  }
  return marker as unknown as DeletionMarker;
}

function isMissingAuthUser(error: unknown): boolean {
  return typeof error === "object" && error !== null &&
    "code" in error && error.code === "auth/user-not-found";
}

class FirebaseAccountDeletionBackend implements AccountDeletionBackend {
  private readonly database = getFirestore();

  async readMarker(userId: string): Promise<DeletionMarker | undefined> {
    const snapshot = await this.requestReference(userId).get();
    if (!snapshot.exists) {
      return undefined;
    }
    const marker = deletionMarkerFrom(snapshot.data());
    if (marker === undefined) {
      throw new Error("Malformed account deletion request");
    }
    return marker;
  }

  async deleteAuthUser(userId: string): Promise<void> {
    await getAuth().deleteUser(userId);
  }

  async checkpointAuthDeletedAndStripRoot(
    userId: string,
    originalMarker: DeletionMarker,
  ): Promise<DeletionMarker> {
    const requestReference = this.requestReference(userId);
    const userReference = this.userReference(userId);

    await this.database.runTransaction(async (transaction) => {
      const requestSnapshot = await transaction.get(requestReference);
      const currentMarker = deletionMarkerFrom(requestSnapshot.data());

      // Another invocation can advance the same idempotent job. Never regress
      // its durable state, but repair the mirrored root fence if necessary.
      if (currentMarker?.state === "completed" ||
          currentMarker?.state === "auth_deleted") {
        transaction.set(userReference, {accountDeletion: currentMarker});
        return;
      }

      // This is the first Firestore-destructive write. It occurs only after
      // deleteAuthUser succeeded or returned auth/user-not-found.
      const authDeletedMarker = {
        state: "auth_deleted",
        workflowVersion: WORKFLOW_VERSION,
        requestedAt: currentMarker?.requestedAt ?? originalMarker.requestedAt,
        authDeletedAt: FieldValue.serverTimestamp(),
      };
      transaction.set(requestReference, authDeletedMarker);
      transaction.set(userReference, {accountDeletion: authDeletedMarker});
    });

    const checkpoint = await this.readMarker(userId);
    if (checkpoint === undefined ||
        (checkpoint.state !== "auth_deleted" &&
         checkpoint.state !== "completed")) {
      throw new Error("Account deletion checkpoint was not persisted");
    }
    return checkpoint;
  }

  async deleteUserSubcollections(userId: string): Promise<void> {
    const collections = await this.userReference(userId).listCollections();
    for (const collection of collections) {
      await this.database.recursiveDelete(collection);
    }
  }

  async markRequestAndRootCompleted(
    userId: string,
    marker: DeletionMarker,
  ): Promise<void> {
    const requestReference = this.requestReference(userId);
    const userReference = this.userReference(userId);

    await this.database.runTransaction(async (transaction) => {
      const requestSnapshot = await transaction.get(requestReference);
      const currentMarker = deletionMarkerFrom(requestSnapshot.data());
      if (currentMarker?.state === "completed") {
        transaction.set(userReference, {accountDeletion: currentMarker});
        return;
      }
      if (currentMarker !== undefined &&
          currentMarker.state !== "auth_deleted") {
        throw new Error("Cannot complete deletion before Auth checkpoint");
      }

      const completedMarker = {
        state: "completed",
        workflowVersion: WORKFLOW_VERSION,
        requestedAt: currentMarker?.requestedAt ?? marker.requestedAt,
        authDeletedAt: currentMarker?.authDeletedAt ?? marker.authDeletedAt,
        completedAt: FieldValue.serverTimestamp(),
      };
      transaction.set(requestReference, completedMarker);
      transaction.set(userReference, {accountDeletion: completedMarker});
    });
    logger.info("Account deletion completed", {userId});
  }

  isMissingAuthUser(error: unknown): boolean {
    return isMissingAuthUser(error);
  }

  private requestReference(userId: string) {
    return this.database.doc(`accountDeletionRequests/${userId}`);
  }

  private userReference(userId: string) {
    return this.database.doc(`users/${userId}`);
  }
}

const deletionBackend = new FirebaseAccountDeletionBackend();

/**
 * Completes a newly created durable request. Normal /users writes never invoke
 * this function; retries always read the request's current checkpoint.
 */
export const processAccountDeletion = onDocumentCreated(
  {
    document: "accountDeletionRequests/{userId}",
    memory: "512MiB",
    retry: true,
    timeoutSeconds: 540,
  },
  async (event) => {
    await runAccountDeletion(event.params.userId, deletionBackend);
  },
);

/**
 * Event delivery retries are finite. This hourly scan resumes any durable
 * request that outlives the trigger's retry window or whose event was lost.
 */
export const sweepAccountDeletions = onSchedule(
  {
    schedule: "every 60 minutes",
    retryCount: 3,
    memory: "512MiB",
    timeoutSeconds: 540,
  },
  async () => {
    const pending = await getFirestore()
      .collection("accountDeletionRequests")
      .where("state", "in", ["requested", "auth_deleted"])
      .get();
    let failures = 0;

    // Bound concurrent recursive deletes while still allowing the sweep to
    // finish if one account is temporarily failing.
    for (let index = 0; index < pending.docs.length; index += 10) {
      const chunk = pending.docs.slice(index, index + 10);
      const results = await Promise.allSettled(
        chunk.map((document) =>
          runAccountDeletion(document.id, deletionBackend)),
      );
      for (let resultIndex = 0; resultIndex < results.length; resultIndex += 1) {
        const result = results[resultIndex];
        if (result.status === "rejected") {
          failures += 1;
          logger.error("Account deletion sweep failed", {
            userId: chunk[resultIndex].id,
            error: result.reason,
          });
        }
      }
    }

    if (failures > 0) {
      throw new Error(`${failures} account deletion(s) remain incomplete`);
    }
  },
);
