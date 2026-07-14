# Requirement: 
- Any change to a service job—including starting/stopping it or changing its parameters—must be reviewed, notified, or approved before it takes effect. This applies when the change is made by someone actively working on the project. Approval is required to prevent the change from disrupting the project's workflow or causing issues later, including any other workflows that depend on that job's output. 

# Expected Behavior:
- When a developer or an associate updates a service job's configuration, the change should not apply immediately.
- The system sends a notification to the designated account manager, including a link to review and approve/reject the change.
- The change takes effect only after one approves it via the provided link.
- If rejected, the change is discarded (or reverted), and any subordinate developer or associate may be notified of the rejection.

---

# Goal : 
## Step 1: To identify the critical entities, because not every entity contains equal weight. 
- Sorting entities and categorizing them on the basis of what they govern. Following:
- Integration/remote-connection config (e.g. `SystemMessageRemote`)
- System-wide behavior toggles (e.g. `SystemProperty`)
- Store-level business rules (e.g. `ProductStoreSetting`)
- Job/scheduling definitions (e.g. `JobSandbox`, `moqui.service.job.*`)
- Reference/lookup or descriptive entities (low risk by default)
Example:
- Integration entity needs field by field review.

## Step 2: Identifying fields
- A. Does this field control connectivity(URLs, creds)/auth(keys,secret)/identity(PK)?
- B. How runtime behaviour is related? (flag:enabled/disabled) - changes the workflow: system's execution path, logic, or processing state. 
- Path Selection: It determines which code branches execute.
- Gatekeeping: It acts as a toggle to allow or block specific processes.
- Operational Mode: It shifts how the system handles data (e.g., switching from "Test" to "Production" mode).
- C. Is the field descriptive only? 
[A and B refers critical fields]

---
# Entities identified as critical entities 
- Definition of critical entities: Entities that can affect the workflow, when changes are done. 

---
![alt text](<Untitled design (2).png>)
---