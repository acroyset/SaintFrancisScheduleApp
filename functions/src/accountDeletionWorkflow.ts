export type DeletionState = "requested" | "auth_deleted" | "completed";

export interface DeletionMarker {
  state: DeletionState;
  workflowVersion: number;
  requestedAt: unknown;
  authDeletedAt?: unknown;
  completedAt?: unknown;
}

export interface AccountDeletionBackend {
  readMarker(userId: string): Promise<DeletionMarker | undefined>;
  deleteAuthUser(userId: string): Promise<void>;
  checkpointAuthDeletedAndStripRoot(
    userId: string,
    marker: DeletionMarker,
  ): Promise<DeletionMarker>;
  deleteUserSubcollections(userId: string): Promise<void>;
  markRequestAndRootCompleted(
    userId: string,
    marker: DeletionMarker,
  ): Promise<void>;
  isMissingAuthUser(error: unknown): boolean;
}

/**
 * Advances one account's durable deletion state machine to completion.
 *
 * The only Firestore-destructive calls are deliberately below deleteAuthUser.
 * Each successful phase is checkpointed by the backend and may safely repeat.
 */
export async function runAccountDeletion(
  userId: string,
  backend: AccountDeletionBackend,
): Promise<void> {
  let marker = await backend.readMarker(userId);
  if (marker === undefined || marker.state === "completed") {
    return;
  }

  if (marker.state === "requested") {
    try {
      await backend.deleteAuthUser(userId);
    } catch (error: unknown) {
      if (!backend.isMissingAuthUser(error)) {
        throw error;
      }
    }
    marker = await backend.checkpointAuthDeletedAndStripRoot(userId, marker);
  }

  // A concurrent invocation may have completed while this invocation was
  // deleting Auth or writing its checkpoint.
  if (marker.state === "completed") {
    return;
  }
  if (marker.state !== "auth_deleted") {
    throw new Error(`Unexpected account deletion state: ${marker.state}`);
  }

  await backend.deleteUserSubcollections(userId);
  await backend.markRequestAndRootCompleted(userId, marker);
}
