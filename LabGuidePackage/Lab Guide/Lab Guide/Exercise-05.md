# Challenge 5 - Audit, recover, and protect data with Delta Lake time travel

### Estimated Duration: 35 Minutes

## Scenario

A simulated corruption event has affected the Silver layer in your Microsoft Fabric medallion architecture. Before downstream orchestration can be trusted again, you must prove what changed, identify the last known good table state, recover the correct version of the Silver dataset, and implement a lightweight backup pattern that can support future investigations or rollback testing.

## Overview

In this challenge, you will investigate version history for the Silver Delta table, compare the corrupted state to an earlier snapshot, recover the table by restoring a verified good version, and create a clone-based backup object that demonstrates operational resilience.

## Objectives

- Task 1: Audit the corrupted Silver table and identify the recovery point
- Task 2: Restore the Silver table and validate recovered business data
- Task 3: Create a clone-based backup pattern for future incidents

## Task 1: Audit the corrupted Silver table and identify the recovery point

In this task, you will use Delta Lake history and read-only time travel to determine which table version represents the last known good Silver state.

1. Sign in to the Microsoft Fabric experience with the lab credentials provided for your sandbox.
   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>
2. Confirm that you are working in the challenge environment associated with **Deployment ID: <inject key="DeploymentID" enableCopy="false"/>**.
3. Open the Lakehouse that contains your Silver layer and locate the Delta table used for curated orders, such as `silver_orders` or the equivalent Silver orders table defined in your earlier challenges.
4. Review the table's Delta history before making any changes. Use a notebook or SQL-capable Spark surface to inspect version history and identify recent write operations, overwrite activity, or other events that explain the corruption.
5. Compare the current table contents with one or more earlier snapshots by using Delta Lake time travel. Your goal is to prove two things:
   1. the current version is not trustworthy, and
   2. an earlier version contains the expected business data.
6. Select the version or timestamp that represents the last known good state and record the evidence you used to justify it, such as row counts, expected values, or absence of the corruption pattern.

> [!Important]
> Delta Lake time travel is read-only. Use it to inspect and verify historical snapshots before you change the live table state.

> [!Tip]
> Start with table history, then compare the current Silver data against a historical version. This reduces the risk of restoring the wrong snapshot.

## Task 2: Restore the Silver table and validate recovered business data

In this task, you will make the verified historical version current again and confirm that recovery succeeded.

1. Restore the Silver Delta table to the version or timestamp you identified in the previous task.
2. Re-run your key business validation checks against the restored table. At minimum, confirm that the corruption symptoms are gone and that the table now matches the known-good state you reviewed during time travel.
3. Review the Delta history again and verify that the restore action created a new versioned event in the table history rather than deleting prior history.
4. Capture concise recovery evidence that demonstrates:
   - the table was corrupted,
   - a specific version was selected for recovery, and
   - the restored current state now passes your verification checks.

> [!Note]
> Delta Lake restore creates a new current version that points back to the selected historical state. It does not erase the fact that the corruption happened.

<validation step="5"/>

## Task 3: Create a clone-based backup pattern for future incidents

In this task, you will create a backup-style clone so the team has a repeatable pattern for safe validation and recovery preparation.

1. Create a separate Delta table that shallow clones the recovered Silver table.
2. Use a clear naming pattern that distinguishes the clone from the operational Silver table and makes its recovery purpose obvious.
3. Confirm that the clone is queryable and reflects the expected point-in-time state at the moment it was created.
4. Document, in your notebook comments or run notes, when this clone pattern is appropriate and what its limitation is in Fabric.
5. Explain why this pattern is useful for troubleshooting, validation, and short-lived backup scenarios, but should not be treated as an unlimited long-term archival strategy.

> [!Important]
> In Microsoft Fabric, shallow clone is fast and storage-efficient because it references the source table's OneLake files. It is useful for recovery testing and point-in-time backup patterns, but it still depends on source file availability.

> [!Tip]
> If your team needs a durable copy that remains independent of future file cleanup operations, use a full copy pattern instead of relying only on shallow clone.

## Summary

You audited the corrupted Silver Delta table, used time travel to identify a trustworthy recovery point, restored the table to a known-good state, and created a clone-based backup pattern to improve resilience for future incidents. These capabilities establish the recovery controls needed before final orchestration and run-state validation are completed in the next challenge.
