# The one bound for a test step that waits on a process, a shell, or a tmux
# event. It stops a hung step and costs nothing otherwise, because every wait
# returns as soon as its event happens. Deadline tests keep their own short
# budgets.
$HangGuard = [TimeSpan]::FromSeconds(30)
$HangGuardMilliseconds = [int] $HangGuard.TotalMilliseconds
$HangGuardSeconds = [int] $HangGuard.TotalSeconds
