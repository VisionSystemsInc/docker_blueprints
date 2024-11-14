# Usage

```
import pyglog
pyglog.initGoogleLogging()
pyglog.installFailureSignalHandler()
pyglog.warning("You've been warned")
import os, signal
os.kill(os.getpid(), signal.SIGSEGV)
```