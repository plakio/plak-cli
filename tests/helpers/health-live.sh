# shellcheck disable=SC2154 # Paths/ports/process variables belong to the caller fixture.
# Sourced only by the opt-in real WordPress/FrankenPHP fixture. Reuses its
# temporary HOME, CA, MariaDB and loopback ports; never touches system services.
health_results="${PLAK_HEALTH_RESULTS_DIR:-$tmpdir/health-results}"
mkdir -p "$health_results"
curl() {
    command curl --connect-to "plak.localhost:443:127.0.0.1:$https_port" "$@"
}
health_isolate_config() {
    python3 - "$CADDYFILE_PATH" "$http_port" "$https_port" "$admin_port" <<'PY'
import sys
p=sys.argv[1]; text=open(p).read()
text=text.replace('{\n','{\n    admin 127.0.0.1:'+sys.argv[4]+'\n    skip_install_trust\n    default_bind 127.0.0.1\n    http_port '+sys.argv[2]+'\n    https_port '+sys.argv[3]+'\n',1)
text=text.replace('frankenphp {','frankenphp {\n        num_threads 2\n        max_threads 4',1)
open(p,'w').write(text)
PY
}
# Retain the real config generator; substitute only service lifecycle with an
# isolated real process so --restart cannot act on the host's systemd/launchd.
eval "$(declare -f regenerate_caddyfile | sed '1s/regenerate_caddyfile/health_original_generate/')"
regenerate_caddyfile() { health_original_generate > "$health_results/generate.log"; health_isolate_config; }
health_stop() {
    [ -z "$web_pid" ] || { kill "$web_pid"; wait "$web_pid" || true; web_pid=""; }
}
start_caddy_service() {
    health_stop
    "$PLAK_TEST_FRANKENPHP" run --config "$CADDYFILE_PATH" >> "$health_results/web.log" 2>&1 &
    web_pid=$!
    for _ in {1..100}; do
        if plak_health_web json > "$health_results/ready.json"; then return 0; fi
        sleep 0.1
    done
    cat "$health_results/web.log" >&2
    return 1
}
plak_health_opcache --json > "$health_results/opcache-before.json"
baseline_pid="$web_pid"
plak_health_opcache set opcache.memory_consumption=256 --yes > "$health_results/saved-only.log"
[ "$web_pid" = "$baseline_pid" ]
plak_health_opcache --json > "$health_results/opcache-saved-only.json"
cp "$PHP_INI_FILE" "$health_results/valid-php.ini"
if plak_health_opcache set opcache.memory_consumption=0 --restart > "$health_results/invalid.log" 2>&1; then exit 1; fi
cmp "$PHP_INI_FILE" "$health_results/valid-php.ini"
[ "$web_pid" = "$baseline_pid" ]
plak_health_opcache set opcache.memory_consumption=256 --restart > "$health_results/restarted.log"
[ "$web_pid" != "$baseline_pid" ]
plak_health_opcache --json > "$health_results/opcache-after.json"
python3 - "$health_results" <<'PY'
import json,sys,pathlib
p=pathlib.Path(sys.argv[1])
before=json.load(open(p/'opcache-before.json')); saved=json.load(open(p/'opcache-saved-only.json')); after=json.load(open(p/'opcache-after.json'))
assert before['source']==saved['source']==after['source']=='web'
assert before['opcache_ini']['opcache.memory_consumption']==saved['opcache_ini']['opcache.memory_consumption']
assert int(after['opcache_ini']['opcache.memory_consumption'])==256
assert after['opcache_configuration']['opcache.memory_consumption'] in (None,256*1024*1024)
if after['opcache_configuration']['opcache.memory_consumption'] is None:
    assert after['opcache_warnings'] and after['opcache_status']['memory_usage']['used_memory'] is None
assert after['opcache_status']['memory_usage']['free_memory']>0
assert 'cache_full' in after['opcache_status']
assert 'hits' in after['opcache_status']['opcache_statistics']
assert 'misses' in after['opcache_status']['opcache_statistics']
PY
plak_health_opcache set opcache.enable=0 --restart > "$health_results/disabled.log"
plak_health_opcache --json > "$health_results/opcache-disabled.json"
python3 - "$health_results/opcache-disabled.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert r['source']=='web' and not r['opcache_enabled'] and r['opcache_status'] is None
PY
health_stop
if plak_health_opcache --json > "$health_results/stopped.json" 2> "$health_results/stopped.log"; then exit 1; fi
plak_health_opcache set opcache.enable=1 --restart > "$health_results/enabled.log"
plak_site_add plain-health --plain --no-reload > "$health_results/plain.log"

# Load both protocols with the same files, OPcache limit and PHP thread pool.
# curl's parallel transfer scheduler can reuse connections and multiplex h2;
# every request validates HTTP status and negotiated version, not just time.
for protocol in h1 h2; do
    printf "\nHTTP2_ENABLED='%s'\n" "$([ "$protocol" = h2 ] && echo 1 || echo 0)" >> "$CONFIG_FILE"
    regenerate_caddyfile
    start_caddy_service
    plak_health_http2 --json > "$health_results/probe-$protocol.json"
    python3 - "$protocol" "$https_port" "$ca" "$health_results" "$web_pid" <<'PY'
import json,sys,subprocess,time,statistics,pathlib
mode,port,ca,out,pid=sys.argv[1:]; directory=pathlib.Path(out)
endpoints=[('dashboard','plak.localhost','/'),('static','plain-health.localhost','/'),
           ('wordpress','ms-subdirectories.localhost','/'),('wp-login','ms-subdirectories.localhost','/wp-login.php'),
           ('wp-assets','ms-subdirectories.localhost','/wp-includes/css/dashicons.min.css')]
def rss():
    try:
        return int(next(line.split()[1] for line in open('/proc/'+pid+'/status') if line.startswith('VmRSS:')))*1024
    except (OSError,StopIteration): return None
samples=[]; initial=rss()
for label,host,path in endpoints:
    for phase,count,concurrency in [('cold',1,1),('warm',100,8),('warm-high',100,16)]:
        args=['curl','--noproxy','*','--cacert',ca,'--silent','--show-error','--fail','--max-time','30',
              '--connect-to',host+':443:127.0.0.1:'+port,'--http2' if mode=='h2' else '--http1.1',
              '--parallel','--parallel-max',str(concurrency),'--write-out','%{json}\n']
        for _ in range(count): args+=['--url','https://'+host+path,'--output','/dev/null']
        start=time.monotonic(); result=subprocess.run(args,capture_output=True,text=True); elapsed=time.monotonic()-start
        (directory/(mode+'-'+label+'-'+phase+'.jsonl')).write_text(result.stdout)
        (directory/(mode+'-'+label+'-'+phase+'.stderr')).write_text(result.stderr)
        records=[json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        assert result.returncode==0 and len(records)==count, (mode,label,phase,result.returncode,result.stderr)
        assert all(r['response_code']==200 and r['http_version']==('2' if mode=='h2' else '1.1') for r in records), (mode,label,phase)
        latencies=sorted(r['time_total']*1000 for r in records)
        samples.append({'endpoint':label,'phase':phase,'requests':count,'concurrency':concurrency,'errors':0,
                        'median_ms':round(statistics.median(latencies),3),'p95_ms':round(latencies[min(len(latencies)-1,int(len(latencies)*.95))],3),
                        'elapsed_s':round(elapsed,3),'requests_per_s':round(count/elapsed,2),'rss_bytes':rss()})
(directory/(mode+'-summary.json')).write_text(json.dumps({'protocol':mode,'initial_rss_bytes':initial,'samples':samples},indent=2))
PY
done
"$PLAK_TEST_FRANKENPHP" version > "$health_results/frankenphp-version.txt"
command curl --version > "$health_results/curl-version.txt"
uname -a > "$health_results/platform.txt"
cp "$CADDYFILE_PATH" "$health_results/evaluated-Caddyfile"
plak_health_opcache --json > "$health_results/opcache-load.json"
if grep -Eiq 'panic|fatal error|segmentation fault' "$health_results/web.log"; then
    echo 'Fatal server signal found during health load validation' >&2; exit 1
fi
echo "Real web OPcache save/restart/disabled/stopped and HTTP1/HTTP2 load tests passed: $health_results"
