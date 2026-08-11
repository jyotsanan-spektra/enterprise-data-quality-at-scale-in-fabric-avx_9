# Challenge 6: Orchestrate the end-to-end medallion pipeline with internal run-state validation

### Estimated Duration: 40 Minutes

## Scenario

You have now built the core Microsoft Fabric data estate for this lab inside your assigned workspace. In Challenge 1, you confirmed the workspace foundation and created or validated the required Fabric items for the medallion design. In Challenges 2 through 5, you implemented the learner-owned ingestion, quality, warehouse, and recovery components. Your final objective is to connect those same learner-created Fabric items into a single orchestration flow that proves the Bronze, Silver, and Gold process can run end to end with observable success and failure behavior entirely inside Fabric.

## Overview

In this challenge, you will use the Fabric items you created earlier in the lab to assemble a pipeline that coordinates CDC ingestion, notebook-driven quality enforcement, and Gold-layer history processing in the correct dependency order. You will then validate both a successful run path and a controlled failure path by reviewing pipeline activity outcomes, run outputs, and resulting data state in your own workspace.

## Objectives

- Task 1: Assemble the orchestration by reusing the Fabric items you created earlier
- Task 2: Add retry-aware failure handling that blocks downstream processing
- Task 3: Prove both successful and failed run behavior with internal Fabric evidence

## Task 1: Assemble the orchestration by reusing the Fabric items you created earlier

In this task, you will build the orchestration flow by connecting the Fabric control-plane items you created or completed in earlier challenges.

1. Sign in to the Microsoft Fabric portal with the lab account assigned to your environment.
   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>
2. Open the Fabric workspace that you reviewed and prepared in Challenge 1, then identify the learner-created items that now make up your medallion implementation.
3. Confirm that the workspace contains, at minimum, the Lakehouse and Warehouse objects you established in Challenge 1, the CDC ingestion asset you completed in Challenge 2, the PySpark quality notebook you completed in Challenge 4, and the Gold customer-dimension load process you completed in Challenge 3.
4. Create a new Fabric pipeline, or complete an unfinished one, inside that same workspace so the orchestration runs against the exact Fabric items you built during the earlier challenges.
5. Add the Bronze ingestion step first, using the ingestion item you created for `Contoso_Operations.Orders`, so the pipeline refreshes the Bronze layer before any downstream validation begins.
6. Add the notebook-based quality gate after Bronze ingestion, and configure the dependency so the quality activity runs only after the ingestion activity succeeds.
7. Add the Gold history-loading step after the quality gate, and bind it to the Warehouse-related process you created earlier so the customer dimension load runs only after the quality path passes.
8. If your Silver promotion is handled separately from the notebook itself, insert that Silver-processing activity between the quality gate and the Gold load and make sure it depends on a successful validation result.
9. Use clear activity names that reflect the learner-created flow, such as Bronze CDC ingestion, Bronze-to-Silver quality gate, Silver promotion, Gold dimension load, and failure evidence logging.
10. Save the pipeline and confirm the canvas shows the intended dependency order across the same workspace items you created in this lab rather than any assumed prebuilt pipeline assets.

> [!Important]
> Microsoft Fabric workspaces act as containers for items such as lakehouses, warehouses, notebooks, and pipelines. In this challenge, continue working only with the items you established in earlier challenges. Do not rely on any unnamed or assumed pre-seeded Fabric control-plane objects.

## Task 2: Add retry-aware failure handling that blocks downstream processing

In this task, you will refine the orchestration so transient execution issues can be retried, while genuine data quality failures still stop the medallion flow.

1. Review the notebook quality gate and the downstream dependencies so the orchestration can clearly distinguish a successful validation outcome from a quality-driven failure.
2. Configure retry behavior only for activities where a retry is operationally appropriate, such as transient execution issues, and avoid a design that would repeatedly rerun a known bad-data condition without surfacing the failure.
3. If your notebook returns an output, status, or exit condition, use that result in the orchestration logic so the pipeline branches consistently based on the quality outcome.
4. Add control-flow logic that explicitly blocks Silver and Gold continuation when the quality gate fails.
5. If required, add an explicit failure path so the overall pipeline run is marked failed with a meaningful message instead of appearing partially successful.
6. Add a logging, annotation, or evidence activity on the failure path so a reviewer can determine which learner-created stage failed and why by reading the pipeline run results.
7. Recheck the dependency model and confirm the pipeline now supports both of these intended outcomes:
   1. A clean-data run that reaches the Gold stage successfully.
   2. A controlled bad-data run that stops downstream processing and leaves visible internal failure evidence in Fabric.

> [!Note]
> Fabric pipelines support dependency-based orchestration and monitoring through activity status, run history, and output details. Use those native capabilities to express the success and failure paths clearly.

## Task 3: Prove both successful and failed run behavior with internal Fabric evidence

In this task, you will validate the orchestration by testing both the success path and the failure path against the Fabric items you created earlier in the lab.

1. Trigger the pipeline with a clean-data scenario and wait for the orchestration to finish.
2. Review the pipeline run details and confirm that the learner-created ingestion, quality, Silver, and Gold steps executed in the dependency order you designed.
3. Capture evidence from run history, activity status, and outputs that proves the successful path completed end to end inside your Fabric workspace.
4. Validate the resulting data state by confirming that Bronze reflects the refreshed CDC load, Silver remains aligned to successful quality checks, and the Warehouse history-processing step completed as expected.
5. Introduce or reuse the controlled quality-failure scenario from the earlier challenges so the orchestration encounters a deliberate validation issue.
6. Run the same pipeline again and confirm that the failure path is activated.
7. Inspect the monitoring details and identify which activity failed, which branch executed next, and whether downstream Silver or Gold processing was correctly blocked.
8. Compare the successful and failed runs and verify that the pipeline provides enough internal evidence to assess behavior without relying on external notification systems.
9. Record the deployment context for your validation evidence: **Deployment ID: <inject key="DeploymentID" enableCopy="false"/>**.

<validation step="Validate orchestration success/failure run states and dependency behavior using internal pipeline evidence."/>

## Summary

In this challenge, you orchestrated the end-to-end medallion process by wiring together the Fabric control-plane items you created throughout the lab. You used your workspace pipeline to coordinate Bronze ingestion, Spark-based quality enforcement, optional Silver promotion, and Gold history loading, then verified both successful and controlled failed outcomes through native Fabric run-state evidence.