# Usage

```
import nglog
nglog.InitializeLogging()
nglog.installFailureSignalHandler()
nglog.warning("You've been warned")
import os, signal
os.kill(os.getpid(), signal.SIGSEGV)
```