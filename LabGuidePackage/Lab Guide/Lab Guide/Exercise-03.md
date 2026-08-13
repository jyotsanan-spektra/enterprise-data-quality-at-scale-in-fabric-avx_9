# Challenge 3: Implement SCD Type 2 history in the Gold Warehouse

### Estimated Duration: 40 Minutes

## Scenario

The Contoso operations team needs the Gold layer to preserve customer attribute history instead of overwriting prior values. In this challenge, you will use the Warehouse item you created in Challenge 1 to build a customer dimension that supports SCD Type 2 behavior, run an initial load, process a change set, and prove that historical and current customer versions are stored correctly.

## Overview

In this challenge, you will open your Fabric Warehouse, create a customer dimension table with surrogate-key and history-tracking columns, load the first version of the customer records, apply a second load that contains customer changes, and validate that changed customers now have expired and current versions side by side.

## Objectives

- Task 1: Create the customer dimension table in the Gold Warehouse
- Task 2: Load the initial customer dimension rows
- Task 3: Apply SCD Type 2 changes and validate history

## Task 1: Create the customer dimension table in the Gold Warehouse

In this task, you will open the Warehouse from Challenge 1 and create the customer dimension structure required for Type 2 history tracking.

1. Open Microsoft Fabric at <https://app.fabric.microsoft.com> and sign in with the lab credentials if you are prompted:
   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>
2. Open the workspace you used earlier in the lab, and then select the Warehouse item you created for the Gold layer in Challenge 1.
3. On the Warehouse ribbon, select **New SQL query** to open the SQL query editor.
4. Create a new dimension table for customer history. Your table must include the following logical elements:
   - A surrogate key column for the warehouse dimension row
   - A customer business key column that remains stable across versions
   - Customer descriptive attributes you plan to track, such as name, city, state, segment, or status
   - An effective start column
   - An effective end column
   - A current-row flag
5. Use a Fabric Warehouse-supported table definition. If you want to use an automatically generated surrogate key, define it with a `BIGINT IDENTITY` column because that is the supported identity pattern for Warehouse in Microsoft Fabric.
6. Run the create-table statement, and then refresh the Warehouse explorer to confirm the customer dimension table appears.
7. Record the deployment context for this lab run using **<inject key="DeploymentID" enableCopy="false"/>** so you can tie your validation evidence to the correct environment.

> [!Important]
> Microsoft Learn documents table creation in Fabric Warehouse through the SQL query editor and notes that `IDENTITY` surrogate keys use the `BIGINT` data type. Keep the dimension in the Warehouse item itself, not in the SQL analytics endpoint of another item.

## Task 2: Load the initial customer dimension rows

In this task, you will populate the first version of the customer dimension so you have a baseline state before any tracked changes occur.

1. Identify the prepared customer source data provided for this lab scenario and review the columns that represent the customer business key and the tracked descriptive attributes.
2. In the SQL query editor, write the initial load statement that inserts one row per customer into your Gold customer dimension.
3. Set the effective start column to the load date or load timestamp used by your implementation.
4. Set the effective end column to an open-ended value that represents the active version in your design.
5. Set the current-row flag so every baseline row is marked as current.
6. Run the initial load.
7. Query the dimension table and confirm that each customer business key currently appears only once.
8. Save or note the baseline row count because you will compare it after the Type 2 change processing step.

> [!Note]
> An initial SCD Type 2 load behaves like a full current snapshot: all rows are inserted as the first active versions. Versioning behavior becomes visible only when a later change set modifies tracked attributes for an existing customer.

## Task 3: Apply SCD Type 2 changes and validate history

In this task, you will process the prepared customer changes by expiring prior rows and inserting replacement current rows, then verify the final state with SQL queries.

1. Review the provided customer change set and identify which customers have tracked attribute changes.
2. In your Warehouse load logic, match incoming rows to the current customer dimension row by business key.
3. For every matched customer whose tracked attributes changed, update the existing current row so it is no longer current and set its effective end value to the processing date or timestamp.
4. Insert a new row for each changed customer with:
   - A new surrogate key
   - The same customer business key
   - The updated attribute values
   - A new effective start value
   - The open-ended effective end value
   - The current-row flag set to true
5. For customers with no tracked attribute changes, do not create duplicate rows.
6. Run the change-processing logic.
7. Query the customer dimension and confirm that at least one changed customer now has two versions tied to the same business key.
8. Run validation queries that prove all of the following:
   - The older row is expired
   - The new row is current
   - Only one current row exists per business key
   - Unchanged customers still have a single row
9. Capture the output of your validation queries for your records.

> [!Tip]
> Microsoft Learn describes the Type 2 pattern as expiring the old version and inserting a new current version rather than updating the descriptive values in place. If your result shows one overwritten row instead of two versions for a changed customer, the dimension is not behaving as Type 2.

<validation step="Validate SCD Type 2 behavior in the customer dimension, including current/expired row states."/>

## Summary

In this challenge, you created a Gold customer dimension in Fabric Warehouse, loaded its initial customer records, applied Type 2 change processing, and verified that changed customers now have both historical and current versions. The Warehouse is now ready to support downstream reporting and orchestration steps that depend on preserved customer history.
