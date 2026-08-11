# Challenge 2: Implement CDC ingestion into the Bronze layer

### Estimated Duration: 40 Minutes

## Scenario
In Challenge 1, you confirmed the target medallion design and created or validated the Fabric control-plane items that will support the rest of the lab. In this challenge, you will build on those learner-created items by implementing incremental ingestion from `Contoso_Operations.Orders` into the Bronze layer. Your objective is to configure a Microsoft Fabric Copy job that writes into the Lakehouse table `bronze_orders_cdc`, establish the initial baseline load, and then prove that a later run captures only source changes.

## Overview
In this challenge, you will return to the workspace, Lakehouse, and related Fabric items that you created or finalized in Challenge 1. You will use those items as the foundation for a CDC-enabled ingestion pattern from the SQL source into your Bronze destination. After the first run establishes the initial snapshot, you will process a prepared source-side change set and confirm that the same ingestion design applies incremental changes rather than reloading the full dataset.

## Objectives
- Task 1: Reuse the Challenge 1 Fabric foundation for Bronze ingestion
- Task 2: Configure and run the initial CDC baseline load
- Task 3: Process and verify incremental CDC changes

## Task 1: Reuse the Challenge 1 Fabric foundation for Bronze ingestion
In this task, you will confirm that Challenge 2 uses only the workspace and data items that you created or validated in Challenge 1.

1. Sign in to the Microsoft Fabric portal with the lab credentials below:
   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>
2. Reopen the Fabric workspace that you used in Challenge 1 and confirm you are working in the same lab context associated with deployment **<inject key="DeploymentID" enableCopy="false"></inject>**.
3. Locate the Lakehouse that you created or validated in Challenge 1 for Bronze and Silver processing. If you named it differently in your implementation, continue with your own Challenge 1 name and do not create a second parallel Lakehouse for this challenge.
4. Confirm that the SQL source connection for `Contoso_Operations` is available in the workspace and that your Challenge 1 design still maps `Orders` into the Bronze layer of the medallion architecture.
5. Create a new Copy job now if you did not already create one in Challenge 1, or complete the existing learner-created job if you left it partially configured. The Copy job must use `Contoso_Operations.Orders` as the source and your existing Lakehouse as the destination.
6. Define the destination as the Delta table `bronze_orders_cdc` inside the Lakehouse from Challenge 1. Ensure your design keeps all Challenge 2 work inside learner-created Fabric items rather than assuming any pre-seeded Lakehouse table, pipeline, notebook, warehouse, or semantic model already exists.
7. Review the copy design and confirm that it is prepared for incremental CDC processing, with the first run establishing the starting snapshot and later runs applying only captured changes.

> [!Important]
> This lab does not assume that Fabric control-plane items were pre-seeded for you. The workspace, Lakehouse, and any related items used here must be the same items you created or validated in Challenge 1.

## Task 2: Configure and run the initial CDC baseline load
In this task, you will configure the incremental copy behavior and run the first load into `bronze_orders_cdc`.

1. Complete the Copy job configuration so it uses CDC-capable incremental copy behavior for the `Orders` table rather than a repeated full refresh pattern.
2. Verify that the write behavior, key handling, and destination mapping support an initial full snapshot on the first run and change-only processing on later runs.
3. Run the Copy job and monitor it to a successful completion state.
4. Open the Lakehouse table `bronze_orders_cdc` and confirm that the first run created the Bronze baseline dataset in your learner-created Lakehouse.
5. Validate the result with execution evidence such as run status, row counts, preview output, or query results that demonstrate the baseline load completed successfully.
6. Record the names of the workspace item, source table, destination table, and load behavior you configured so you can compare them against the incremental run in the next task.

> [!Note]
> In Microsoft Fabric Copy job CDC patterns, the first run establishes the initial full snapshot. Subsequent runs process captured inserts, updates, and deletes from the source rather than rebuilding the destination from scratch.

## Task 3: Process and verify incremental CDC changes
In this task, you will prove that the same ingestion design captures only source changes after the baseline load exists.

1. Trigger or apply the prepared source-side change set for `Contoso_Operations.Orders` that is provided in the lab environment for CDC validation.
2. Rerun the same Copy job against the same learner-created Lakehouse destination without replacing the Lakehouse, recreating the table under a different name, or building a second ingestion path.
3. Review the run details and confirm that the second execution reflects incremental behavior against the existing `bronze_orders_cdc` table.
4. Reopen `bronze_orders_cdc` and verify that the table now reflects the expected changes from the prepared source delta.
5. Compare the post-run state to your baseline evidence and confirm that the result demonstrates change capture rather than a full reload.
6. Capture final proof for this challenge by showing both the successful rerun state and the before-and-after Bronze table evidence that supports your CDC conclusion.

<validation step="CDC ingestion outcomes"/>
<question>

## Summary
In this challenge, you built on the workspace and Lakehouse foundation established in Challenge 1 to implement CDC ingestion for `Contoso_Operations.Orders`. You configured a Copy job that writes to `bronze_orders_cdc`, validated the initial baseline load, and then proved that the same design captures incremental changes in your learner-created Bronze environment.