# Entity level Approval Detection and Scenario Creation What could go wrong? 
- Currently a product manager or an associate can make changes in the DB entities directly example: `ServiceJob` and `ServiceJobParameter`.
- Here I have listed down the fields and their criticality, as not all fields will be needing approval for changes.
- This doc will focus on the failure scenarios that can occur due to wrong data entered/updated by the Product owner. 
- The scenarios will be based upon the worst case scenarios.
- 
Job Name
Cron
Service Name
Paused
Priority
Retry Time

# Entity name: "service_job" | service call job | scheduled job runner
# Fields List and severity:
JOB_NAME VARCHAR - 
DESCRIPTION VARCHAR
SERVICE_NAME VARCHAR - `CRITICAL`
TRANSACTION_TIMEOUT DECIMAL
TOPICVAR CHAR
LOCAL_ONLY CHAR
CRON_EXPRESSION VARCHAR
FROM_DATE DATETIME
THRU_DATE DATETIME
REPEAT_COUNT DECIMAL
PAUSED CHAR
EXPIRE_LOCK_TIME DECIMAL
MIN_RETRY_TIME DECIMAL
PRIORITY DECIMAL
PARENT_JOB_NAME VARCHAR
JOB_TYPE_ENUM_ID VARCHAR
PERMISSION_GROUP_ID VARCHAR
INSTANCE_OF_PRODUCT_ID VARCHAR
LAST_UPDATED_STAMP DATETIME
CREATED_STAMP DATETIME

# Field level Scenarios:
- serviceName

## Field Name: 'SERVICE_NAME' [severity: `CRITICAL`]
- A bad service name kills all lower priority jobs.
- No row is created in `ServiceJobRun` entity for failed job runs.

## Field Name: 'TRANSACTION_TIMEOUT' [severity: `CRITICAL`]
- Explanation: If  we check "ServiceJob" entity field: "transactionTimeout", we find that the field value is set in the database and picked from database entity: "ServiceJob" whenever needed. But here is the catch, if the project owner or associate who wants to perform some job by running that service, and forgot to set the parameter value in "transactionTimeout" field, then the default value is taken, refer "ServiceCallJobImpl.groovy:153" => transactionTimeout = (serviceJob.transactionTimeout ?: 1800). The default time set is 30 minutes if left empty by a developer/associate which is applied to the entire service call transaction, it is a hardcoded value which may be a good time  to complete a service but may malperform for a service performing heavy tasks which takes more than 30 minutes to complete operatons. Also if the user has set time which is very less, this can also be a reason for transaction timeout. Therefore the transaction manager forcefully rolls back the entire service call when the deadline is crossed. But any sub-services that used `requireNewTransaction=true` have **already committed** — leaving data partially written with no rollback possible for those writes.

### Scenarios: Changing values in 'TRANSACTION_TIMEOUT' affects the workflow in certain ways:
- Left empty → default 1800s (30 min) applies — may still timeout for very heavy jobs.
- Set too low → timeout too soon for the job's actual duration.
- Sub-service partial writes → requireNewTransaction=true sub-calls already committed before the parent TX rolled back.
- Exception caught softly: After the rollback, the exception is caught softly at line 247–249 so the job doesn't crash the scheduler, It silently records hasError='Y' on the ServiceJobRun record. This means no alert fires automatically unless a topic is configured. This makes the partial-write data corruption invisible until someone manually checks Job Runs history.
---
## Field Name: 'MIN_RETRY_TIME' [severity: `CRITICAL`]
- If the minimum retry time is set very less(~0 seconds): There is a risk that external system is touched through an api call or SFTP request every 60 seconds, until the minRetryTime is fixed or external system rate limit is reached.
- The default retry time is 5 minutes. [Refer: Long minRetryTime = (Long) serviceJob.minRetryTime ?: 5L]

### Scenario: 
- Set minRetryTime=0 [Example service job: "poll_SystemMessageFileSftp_OMSFulfillmentFeed"]. After one SFTP timeout error, the job retries every 60 seconds. Instead of waiting, hitting the remote SFTP server constantly. 

#### Need to check more on this one:
Detectability: Log info message "Not retrying job..." only fires when the check passes (i.e., it's skipped). When retrying too fast, the skip doesn't happen — only ServiceJobRun.hasError='Y' rows accumulate rapidly.