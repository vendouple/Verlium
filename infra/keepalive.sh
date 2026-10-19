#!/usr/bin/env bash
# Oracle may reclaim an Always Free VM whose CPU, network AND memory stay below 20% (95th percentile)
# for 7 days. Run from cron every 10 minutes to keep a modest CPU burst on record:
#   */10 * * * * /opt/verlium/infra/keepalive.sh >/dev/null 2>&1
# ~90 s of one-core work per 10 min keeps the 95th percentile above the threshold on a 2-OCPU shape.
timeout 90 sh -c 'while :; do :; done'
curl -fsS http://127.0.0.1:8000/health >/dev/null || systemctl restart verlium
