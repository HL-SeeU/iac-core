"""Local Docker integration test; fake endpoints never contact Grafana Cloud."""

import base64
import gzip
import json
import math
import pathlib
import re
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


ALLOY_IMAGE = "grafana/alloy:v1.20.1"
PYTHON_IMAGE = "python:3.13-alpine"


def serve(mode):
    records = []
    state = {"series": 1}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            if mode == "--sink":
                body = json.dumps(records).encode()
                content_type = "application/json"
            else:
                body = (
                    "# TYPE traefik_service_requests_total counter\n"
                    + "".join(
                        f'traefik_service_requests_total{{service="test-{i}",code="200"}} 1\n'
                        for i in range(state["series"])
                    )
                    + "# TYPE unwanted_metric_total counter\nunwanted_metric_total 1\n"
                ).encode()
                content_type = "text/plain; version=0.0.4"
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            body = self.rfile.read(int(self.headers["Content-Length"]))
            if mode == "--sink":
                records.append({
                    "path": self.path,
                    "auth": self.headers.get("Authorization"),
                    "encoding": self.headers.get("Content-Encoding"),
                    "body": base64.b64encode(body).decode(),
                })
            else:
                value = json.loads(body)
                if isinstance(value, dict):
                    state["series"] = value["series"]
                else:
                    for line in value:
                        print(line, flush=True)
            self.send_response(200)
            self.end_headers()

    ThreadingHTTPServer(("0.0.0.0", 8080 if mode == "--sink" else 8082), Handler).serve_forever()


def snappy_decode(data):
    """Decode raw Snappy blocks used by Prometheus and Loki protobuf writes."""
    pos = 0
    while data[pos] & 128:
        pos += 1
    pos += 1
    result = bytearray()
    while pos < len(data):
        tag = data[pos]
        pos += 1
        kind = tag & 3
        if kind == 0:
            length = tag >> 2
            if length >= 60:
                size = length - 59
                length = int.from_bytes(data[pos:pos + size], "little")
                pos += size
            length += 1
            result.extend(data[pos:pos + length])
            pos += length
            continue
        if kind == 1:
            length = 4 + ((tag >> 2) & 7)
            offset = ((tag & 224) << 3) | data[pos]
            pos += 1
        else:
            length = 1 + (tag >> 2)
            size = 2 if kind == 2 else 4
            offset = int.from_bytes(data[pos:pos + size], "little")
            pos += size
        for _ in range(length):
            result.append(result[-offset])
    return bytes(result)


class ObservabilityTest(unittest.TestCase):
    def test_local_pipelines(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        prefix = "iac-observe-test-" + uuid.uuid4().hex[:10]
        containers = []
        network_created = False

        def docker(*args, check=True, input=None):
            result = subprocess.run(
                ["docker", *args], input=input, text=True, capture_output=True,
                check=check, timeout=180,
            )
            return result.stdout + (result.stderr if args[0] == "logs" else "")

        def request(container, url, body=None):
            code = (
                "import sys, urllib.request; "
                "data=sys.stdin.read(); "
                f"req=urllib.request.Request({url!r}, "
                "data=None if not data else data.encode(), headers={'Content-Type':'application/json'}); "
                "r=urllib.request.urlopen(req, timeout=5); "
                "print(r.read().decode())"
            )
            return docker("exec", "-i", container, "python", "-c", code, input=body or "")

        def wait_for(callback, description, timeout=75):
            deadline = time.monotonic() + timeout
            last_error = None
            while time.monotonic() < deadline:
                try:
                    value = callback()
                    if value:
                        return value
                except subprocess.CalledProcessError as error:
                    last_error = error.stderr
                time.sleep(1)
            self.fail(f"Timed out waiting for {description}: {last_error}")

        with tempfile.TemporaryDirectory(prefix="iac-observe-") as folder:
            directory = pathlib.Path(folder)
            cloud = {
                "metrics_url": "http://sink:8080/api/prom/push",
                "metrics_username": "1",
                "logs_url": "http://sink:8080/loki/api/v1/push",
                "logs_username": "2",
                "otlp_url": "http://sink:8080/otlp",
                "otlp_username": "3",
            }
            template = str(root / "modules" / "observability" / "config.alloy.tftpl")
            expression = (
                f"jsonencode(templatefile({json.dumps(template)}, "
                f"{{cloud={json.dumps(cloud)}, traefik_name=\"{prefix}-source\", instance=\"test\"}}))"
            )
            rendered = subprocess.run(
                ["terraform", f"-chdir={folder}", "console", "-no-color"],
                input=expression, text=True, capture_output=True, check=True, timeout=30,
            )
            config = json.loads(json.loads(rendered.stdout))
            # Faster scrapes only in this isolated test.
            config = config.replace(
                'scrape_interval = "60s"',
                'scrape_interval = "2s"\n  scrape_timeout = "1s"',
            )
            (directory / "config.alloy").write_text(config, encoding="utf-8")
            (directory / "cloud-token").write_text("test-token", encoding="utf-8")
            mount = f"type=bind,source={folder},target=/etc/alloy,readonly"
            docker("run", "--rm", "--mount", mount, ALLOY_IMAGE, "validate", "/etc/alloy/config.alloy")
            try:
                docker("network", "create", "--internal", prefix)
                network_created = True
                for suffix, mode, alias in [
                    ("sink", "--sink", "sink"),
                    ("source", "--fixture", f"{prefix}-source"),
                ]:
                    name = f"{prefix}-{suffix}"
                    containers.append(name)
                    docker(
                        "run", "-d", "--name", name, "--network", prefix,
                        "--network-alias", alias, "--mount",
                        f"type=bind,source={pathlib.Path(__file__).resolve()},target=/test.py,readonly",
                        PYTHON_IMAGE, "python", "/test.py", mode,
                    )
                sink, source = containers
                wait_for(lambda: request(sink, "http://127.0.0.1:8080/"), "fake Cloud")
                wait_for(lambda: request(source, "http://127.0.0.1:8082/metrics"), "metrics fixture")
                alloy = prefix + "-alloy"
                containers.append(alloy)
                docker(
                    "run", "-d", "--name", alloy, "--network", prefix,
                    "--network-alias", "alloy", "--mount", mount,
                    "--mount", "type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock,readonly",
                    ALLOY_IMAGE, "run", "--disable-reporting",
                    "--server.http.listen-addr=127.0.0.1:12345", "/etc/alloy/config.alloy",
                )

                def alloy_http(path):
                    if docker("inspect", "-f", "{{.State.Status}}", alloy).strip() != "running":
                        self.fail("Alloy exited:\n" + docker("logs", alloy, check=False))
                    command = (
                        "exec 3<>/dev/tcp/127.0.0.1/12345; "
                        f"printf 'GET {path} HTTP/1.0\\r\\nHost: localhost\\r\\n\\r\\n' >&3; "
                        "cat <&3"
                    )
                    return docker("exec", alloy, "/usr/bin/bash", "-ec", command)

                wait_for(lambda: "200 OK" in alloy_http("/-/ready"), "Alloy readiness")
                # Allow Docker discovery to attach before emitting access logs.
                time.sleep(3)

                def line(status, duration, router):
                    return json.dumps({
                        "DownstreamStatus": status, "Duration": duration,
                        "RouterName": router,
                    }, separators=(",", ":"))

                important = [
                    line(400, 1, "error-400"), line(500, 1, "error-500"),
                    line(200, 1_000_000_000, "slow-boundary"),
                ]
                boundary = json.dumps({
                    "DownstreamStatus": 500, "Duration": 1,
                    "RouterName": "size-boundary", "padding": "",
                }, separators=(",", ":"))
                boundary = boundary[:-2] + "x" * (4096 - len(boundary)) + '"}'
                self.assertEqual(len(boundary.encode()), 4096)
                important.append(boundary)
                started = time.monotonic()
                request(source, "http://127.0.0.1:8082/emit", json.dumps(important))
                time.sleep(3)
                ordinary = [line(200, 999_999_999, f"normal-{i}") for i in range(5000)]
                oversized = boundary.replace("size-boundary", "size-boundaryx")
                self.assertEqual(len(oversized.encode()), 4097)
                ordinary += [oversized, '{"level":"error","msg":"not an access log"}']
                request(source, "http://127.0.0.1:8082/emit", json.dumps(ordinary))

                trace = json.dumps({"resourceSpans": [{"scopeSpans": [{"spans": [{
                    "traceId": "01" * 16, "spanId": "02" * 8, "name": "local-test-span",
                    "kind": 2, "startTimeUnixNano": str(time.time_ns()),
                    "endTimeUnixNano": str(time.time_ns() + 1_000_000),
                }]}]}]})
                request(source, "http://alloy:4318/v1/traces", trace)

                def received():
                    records = json.loads(request(sink, "http://127.0.0.1:8080/"))
                    paths = {entry["path"] for entry in records}
                    return records if {
                        "/api/prom/push", "/loki/api/v1/push", "/otlp/v1/traces",
                    } <= paths else None

                records = wait_for(received, "all three exports")
                time.sleep(3)
                records = received()
                payloads = {}
                for entry in records:
                    path = entry["path"]
                    username = "1" if path == "/api/prom/push" else "2" if path == "/loki/api/v1/push" else "3"
                    auth = "Basic " + base64.b64encode(f"{username}:test-token".encode()).decode()
                    self.assertEqual(entry["auth"], auth)
                    body = base64.b64decode(entry["body"])
                    if entry["encoding"] == "gzip":
                        body = gzip.decompress(body)
                    if path != "/otlp/v1/traces":
                        body = snappy_decode(body)
                    payloads[path] = payloads.get(path, b"") + body
                self.assertIn(b"traefik_service_requests_total", payloads["/api/prom/push"])
                self.assertNotIn(b"unwanted_metric_total", payloads["/api/prom/push"])
                logs = payloads["/loki/api/v1/push"]
                for marker in [b"error-400", b"error-500", b"slow-boundary", b'"size-boundary"']:
                    self.assertIn(marker, logs)
                self.assertNotIn(b"size-boundaryx", logs)
                self.assertNotIn(b"not an access log", logs)
                self.assertNotIn(b"priority=", logs)
                self.assertLessEqual(
                    logs.count(b'"DownstreamStatus":'),
                    10 + math.ceil(2 * (time.monotonic() - started)),
                )
                self.assertIn(b"local-test-span", payloads["/otlp/v1/traces"])
                metrics = alloy_http("/metrics")
                sampled = sum(
                    float(value) for labels, value in re.findall(
                        r'loki_process_dropped_lines_total\{([^}]+)\}\s+([0-9.e+]+)', metrics
                    ) if 'reason="normal_request_sampling"' in labels
                )
                self.assertGreater(sampled, 4200)
                self.assertLess(sampled, 4800)

                def exceeded_scrapes():
                    return sum(float(value) for value in re.findall(
                        r"prometheus_target_scrapes_exceeded_sample_limit_total(?:\{[^}]*\})?\s+([0-9.e+]+)",
                        alloy_http("/metrics"),
                    ))

                self.assertEqual(exceeded_scrapes(), 0)
                # The extra unwanted metric still counts toward the raw scrape limit.
                request(source, "http://127.0.0.1:8082/series", json.dumps({"series": 7499}))
                time.sleep(4)
                self.assertEqual(exceeded_scrapes(), 0)
                request(source, "http://127.0.0.1:8082/series", json.dumps({"series": 7500}))
                wait_for(lambda: exceeded_scrapes() > 0, "scrape failure above 7,500 samples")
            except Exception:
                for container in containers:
                    print(docker("logs", "--tail", "30", container, check=False), file=sys.stderr)
                raise
            finally:
                for container in reversed(containers):
                    docker("rm", "-f", container, check=False)
                if network_created:
                    docker("network", "rm", prefix)


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] in ("--sink", "--fixture"):
        serve(sys.argv[1])
    else:
        unittest.main()
