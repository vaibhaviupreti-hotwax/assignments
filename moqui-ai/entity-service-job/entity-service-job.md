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

## SERVICE_NAME VARCHAR - `CRITICAL`
- A bad service name kills all lower priority jobs.
- No row is created in `ServiceJobRun` entity for failed job runs.

