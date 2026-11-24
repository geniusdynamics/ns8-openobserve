# ns8-openobserve

[OpenObserve](https://openobserve.ai) for [NethServer 8](https://github.com/NethServer/ns8-core).
It stores and searches logs, metrics and traces. The module runs OpenObserve
(version pinned in `build-images.sh`) in standalone mode with local disk
storage, behind the NS8 Traefik reverse proxy.

## Install

On the leader node:

```sh
add-module ghcr.io/geniusdynamics/openobserve:latest 1
```

The command prints the new module ID, for example `openobserve1`.

## Configure

Use the module Settings page, or the CLI:

```sh
api-cli run module/openobserve1/configure-module --data '{"host":"openobserve.example.org","lets_encrypt":false,"http2https":true}'
```

| Field | Description |
|---|---|
| `host` | Fully qualified hostname, must resolve to the node and not be used by another Traefik route |
| `lets_encrypt` | Request a Let's Encrypt certificate (DNS must already point to the node) |
| `http2https` | Redirect HTTP to HTTPS (default `true`) |

`get-configuration` returns the same fields plus `root_credentials_set`. It
never returns secrets.

## Credentials

On install the module generates the initial root user (`admin@example.org`)
and a random password. They are stored once in `state/openobserve.env` (mode
0600), passed to the container with `--env-file`, included in the backup, and
never written to Redis, logs, command arguments or action output. To read them,
run as root on the node:

```sh
runagent -m openobserve1 openobserve-initial-credentials
```

OpenObserve keeps the root password in its own database after the first start.
If you change it in the web UI, the command still shows the original one. Create
dedicated users or service accounts in OpenObserve for each ingestion client.

## Ingestion

The same Traefik route serves the web UI and the ingestion API. Every request
must authenticate with HTTP basic authentication, so the endpoint is safe to
expose over HTTPS. Use a dedicated user instead of the root account.

JSON logs:

```sh
curl -u 'user@example.org:PASSWORD' -H 'Content-Type: application/json' \
  -d '[{"level":"info","message":"hello"}]' \
  https://openobserve.example.org/api/default/mystream/_json
```

OTLP over HTTP (logs, metrics, traces; protobuf):

```sh
export OTEL_EXPORTER_OTLP_ENDPOINT=https://openobserve.example.org/api/default
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $(printf '%s' 'user@example.org:PASSWORD' | base64 -w0)"
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

Endpoints are `/api/default/v1/logs`, `/api/default/v1/metrics` and
`/api/default/v1/traces`. OTLP over gRPC is not exposed.

## Backup and restore

`state/openobserve.env` and an archive of the `openobserve-data` volume
(`state/openobserve-data.tar`) are backed up. Before each backup
`module-dump-state` stops the service briefly, archives the volume, and starts
it again, so the data is consistent. `module-cleanup-state` deletes the
archive afterwards. Restore requires an empty data volume (a new module) and
reapplies the Traefik route without Let's Encrypt; enable it again in
Settings once DNS points to the new node. Clone copies the state and volume
and also keeps Let's Encrypt disabled.

## Update

Update the module from the NS8 Software Center, or:

```sh
api-cli run update-module --data '{"module_url":"ghcr.io/geniusdynamics/openobserve:latest","instances":["openobserve1"],"force":true}'
```

The update restarts the service if it is running. Image versions are tracked
by Renovate through the `org.nethserver.images` label.

## Troubleshooting

```sh
runagent -m openobserve1 systemctl --user status openobserve.service
journalctl -u user@$(id -u openobserve1).service -f
runagent -m openobserve1 curl -fsS http://127.0.0.1:$(runagent -m openobserve1 printenv TCP_PORT)/healthz
```

- Service restarts at start: check the journal, the health check waits up to
  110 seconds.
- Cannot log in: show the original credentials as above; a password changed
  in the UI is not reflected there.
- Settings rejects the hostname: it is already used by another Traefik route.

## Test

Robot Framework tests are in `tests/` and run against a NS8 node:

```sh
./test-module.sh <leader-node-ip> ghcr.io/geniusdynamics/openobserve:<tag>
```

The CI workflow "Test module on QEMU" runs the same suite on a throwaway node.
