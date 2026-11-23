# OpenObserve for NS8

OpenObserve collects and searches logs, metrics and traces. This module runs
OpenObserve 1.1.2 in standalone mode behind the NS8 reverse proxy.

Configure a DNS hostname and certificate in Settings. The first-start root
account uses `admin@example.org` and a generated password. Retrieve the
initial credentials on the instance's node:

```sh
runagent -m openobserve1 openobserve-initial-credentials
```

Change the password in OpenObserve after the first login. The command displays
the original bootstrap password. Backups stop the service briefly to archive
its data consistently. Restore requires an empty data volume.
