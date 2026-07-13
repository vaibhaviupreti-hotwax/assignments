# Date of creation: Jul 11, 2026

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

