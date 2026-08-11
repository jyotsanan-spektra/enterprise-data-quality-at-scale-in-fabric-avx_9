# Challenge 3: Implement SCD Type 2 history in the Gold Warehouse

### Estimated Duration: 40 Minutes

## Scenario

In Challenge 1, you confirmed the Fabric workspace and created or validated the medallion-aligned control-plane items that this lab uses. In this challenge, you will build on those learner-created Fabric items by implementing SCD Type 2 history tracking in the Gold warehouse customer dimension so customer attribute changes create new current rows while preserving prior versions for historical analysis.

## Overview

In this challenge, you will use the workspace and Warehouse item you established earlier in the lab, define the Gold customer dimension for history tracking, implement an incremental SCD Type 2 load pattern, and validate that changed customers retain both current and expired versions.

## Objectives

- Task 1: Extend the Gold Warehouse customer dimension for history tracking
- Task 2: Implement the incremental SCD Type 2 load pattern
- Task 3: Validate current and expired customer versions

## Task 1: Extend the Gold Warehouse customer dimension for history tracking

In this task, you will build on the Microsoft Fabric items you created or confirmed in Challenge 1 and prepare the Gold dimension design for historical tracking.

1. Sign in to Microsoft Fabric with the lab-provided account linked to your sandbox. When prompted for credentials, use:
   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>
2. Open the same Fabric workspace you used in Challenge 1, and locate the Warehouse item that you created or validated there for the Gold layer.
3. Confirm that you will use that existing learner-created Warehouse item for this challenge rather than relying on any pre-seeded Gold warehouse objects.
4. Create or update a customer dimension table in your Warehouse so it supports SCD Type 2 history instead of in-place overwrite behavior.
5. Ensure the dimension design includes a surrogate key, a stable customer business key, valid-from and valid-to fields, and a current-row indicator so multiple versions of the same customer can coexist.
6. Verify that your design supports one current row and zero or more expired rows for each customer business key.
7. Record the deployment context for your run using **Deployment ID: <inject key="DeploymentID" enableCopy="false"/>** so you can reference it during validation.

> [!Important]
> Microsoft Learn guidance for Fabric Warehouse recommends preserving surrogate-keyed dimensions incrementally. For SCD Type 2 dimensions, avoid truncate-and-reload patterns that would break historical versions and downstream fact relationships.

## Task 2: Implement the incremental SCD Type 2 load pattern

In this task, you will load customer changes into the Warehouse item from Challenge 1 by expiring prior versions and inserting new current rows.

1. Use the customer source and staging data available in your lab environment to identify which customer attributes should be treated as Type 2 changes.
2. Build or complete an incremental load process in your Fabric solution that compares incoming customer records with the current customer dimension rows by business key.
3. For customers that do not yet exist in the dimension, insert new rows with a surrogate key, a valid-from value, an open-ended valid-to value, and the current-row indicator set to true.
4. For customers whose tracked attributes have changed, expire the existing current row by setting its valid-to value to the processing date or timestamp and changing the current-row indicator to false.
5. Insert a replacement current row for each changed customer with a new surrogate key, updated attribute values, a new valid-from value, and the current-row indicator set to true.
6. Run the incremental load against the prepared customer changes and confirm that your process updates only the affected dimension members instead of rebuilding the entire table.

> [!Note]
> Microsoft Learn describes SCD Type 2 handling in Fabric as a pattern where the prior current row is expired and a new versioned row is inserted. This preserves point-in-time history while keeping exactly one row current for a business key.

## Task 3: Validate current and expired customer versions

In this task, you will verify that the customer dimension in your learner-created Warehouse now preserves history correctly.

1. Query the customer dimension in the same Warehouse item from Challenge 1 and inspect at least one customer affected by the prepared incremental change set.
2. Confirm that the changed customer now has multiple dimension rows tied to the same business key.
3. Verify that the prior version is no longer current, that the latest version is marked current, and that the valid-from and valid-to values reflect the load event.
4. Confirm that unchanged customers still have a single current row and were not duplicated unnecessarily.
5. Capture query evidence that proves surrogate key versioning, business key continuity, effective dating, and current-versus-expired row state.

<validation step="Validate SCD Type 2 behavior in the customer dimension, including current/expired row states."/>

## Summary

In this challenge, you extended the Fabric Warehouse item you created or validated earlier in the lab and implemented SCD Type 2 history tracking for the Gold customer dimension. You confirmed that incremental customer changes create new current rows, prior versions are expired correctly, and historical context is preserved for downstream reporting and analysis.