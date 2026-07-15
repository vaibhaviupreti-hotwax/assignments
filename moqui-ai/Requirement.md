# Requirement: 
- Any change to a service job—including starting/stopping it or changing its parameters—must be reviewed, notified, or approved before it takes effect. This applies when the change is made by someone actively working on the project. Approval is required to prevent the change from disrupting the project's workflow or causing issues later, including any other workflows that depend on that job's output. 

# Expected Behavior:
- When a developer or an associate updates a service job's configuration, the change should not apply immediately.
- The system sends a notification to the designated account manager, including a link to review and approve/reject the change.
- The change takes effect only after one approves it via the provided link.
- If rejected, the change is discarded (or reverted), and any subordinate developer or associate may be notified of the rejection.

---

## Goal : 
### Step 1: To identify the critical entities, because not every entity contains equal weight. 
- Sorting entities and categorizing them on the basis of what they govern. Following:
- Integration/remote-connection config (e.g. `SystemMessageRemote`)
- System-wide behavior toggles (e.g. `SystemProperty`)
- Store-level business rules (e.g. `ProductStoreSetting`)
- Job/scheduling definitions (e.g. `JobSandbox`, `moqui.service.job.*`)
- Reference/lookup or descriptive entities (low risk by default)
Example:
- Integration entity needs field by field review.

### Step 2: Identifying fields
- A. Does this field control connectivity(URLs, creds)/auth(keys,secret)/identity(PK)?
- B. How runtime behaviour is related? (flag:enabled/disabled) - changes the workflow: system's execution path, logic, or processing state. 
- Path Selection: It determines which code branches execute.
- Gatekeeping: It acts as a toggle to allow or block specific processes.
- Operational Mode: It shifts how the system handles data (e.g., switching from "Test" to "Production" mode).
- C. Is the field descriptive only? 
[A and B refers critical fields]

---
## Entities identified as critical entities 
- Definition of critical entities: Entities that can affect the workflow, when changes are done. 
[TO BE ADDED...]
- ...
- ...
- ...
---
## Controlled Configuration Change Approval Flow
- Architecture for controlled configuration changes where modifications to critical entities are intercepted, staged, evaluated, and only then committed to the database.

![Config Change Approval Flow](moqui-ai/config-change-approval-flow.png)
---
## Findings: JSON payload.
- I checked the job manager app to check how the payload is created and sent to the backend.
- There is a shared api :
  ```js
  async updateJob(payload: any) {
      return await api({
        url: `admin/serviceJobs/${payload.jobName}`,
        method: "PUT",
        data: payload,
      });
    },
  ```
- URL path: admin/serviceJobs/<jobName>
- Method: PUT
- Body: the full payload object, serialized as JSON
- Headers: authorization + Content-Type: application/json
---
- The Caller method invokes the api and passes the job name with the api endpoint, and this method does not perform any operation; rather, it passes the payload(body) straightaway to the backend.
- NOTE: Here is the place where we need to apply validity checks and make decision to pass the payload JSON to the backend or to create a task of it and pass the JSON - diff to a staging area/ we call it an Entity group here (one Entity for service job changes and one for service job parameter changes) 
- But if the caller passes:
```js
store.updateJob({
  jobName: "myJob",
  description: "desc",
  cronExpression: "0 0 * * *",
  paused: "N",
  serviceJobParameters: [...]
});
```
- In the above case, the backend receives all of those fields

## STAGE FIRST, APPROVE LATER..
### Some points to keep in mind while designing the architecture:
- Initially identify "Critical Entities" and "Low Risk Entities".
- Changes to Job configuration should not be applied immediately (hold/create a task/staging area).
- There should be a need for approval for the risky changes.
- There should be a proper flow to keep the status, to maintain the flow of review/reject/approve.
- Change types should be handled separately: "Configuration changes" (ex: Edit) and "Runtime action" (ex: start/stop).
- Rules should be made on a risk basis, not an entity-based. Risk can be further classified as High risk, Medium Risk, and low risk.
- The staging area should contain [requestedBy, change, beforeValue, afterValue, approvalState, auditTrail]. I found an entity that resembles and can be referred to for this purpose: "EntityAuditLog" entity.
- There should be runtime diff check rather than entity based (this is static and if multiple users are requesting change then there will be a new problem to decide the priority for the change, "Who will get the priority? problem.")
  
### Example staging JSON:
```json
{
  "requestType": "SERVICE_JOB_UPDATE",
  "target": {
    "entity": "serviceJob",
    "jobName": "myJob"
  },
  "changes": [
    {
      "field": "cronExpression",
      "before": "0 0 * * *",
      "after": "0 12 * * *"
    },
    {
      "field": "paused",
      "before": "N",
      "after": "Y"
    }
  ],
  "requestedBy": "user123",
  "reason": "schedule update",
  "riskLevel": "HIGH"
}
```















