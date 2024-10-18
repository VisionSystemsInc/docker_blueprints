# Usage

```
import glog11
glog11.initGoogleLogging()
glog11.installFailureSignalHandler()
glog11.warning("You've been warned")
import os, signal
os.kill(os.getpid(), signal.SIGSEGV)
```