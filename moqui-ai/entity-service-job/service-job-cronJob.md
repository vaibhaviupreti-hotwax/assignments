# Changes done in CRON. 
- cron/crond - cron daemon wakes up every minute and checks modification time of crontab/ directory, reload updated files instantly(without service restart).

- cron change: current execution is not killed
- cron change: It will run completion
- cron change: New Schedule will be applied only to future execution.

- Shortening the interval:(ex: 2 hrs to 15 min) - will increase execution frequency.
- Shortening the interval: If script is resource heavy in the above case it can cause: CPU, memory and disk spikes.

- Race condition: Job takes 30 minutes to complete, next run is in 20 minutes.
- Race condition: Multiple instance of script will run simultanously and can cause "data corruption, DB locks and memory exhausion".
- Race condition - Solution: Locking mech(ex:flock).
- flock: "*/15**** flock -n /tmp/myscriptlock /path/to/script.sh"

- Syntax errors: Any typo will be logged as syntax error in system logs ["/var/log/syslog" or "/var/log/error"] and it will completely refuse to run the updated job.
- Syntax errors - Solution: We need to use "crontab -e": it forces syntax check upon saving previous broken expression from being deployed. 

