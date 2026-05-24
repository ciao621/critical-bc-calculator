from __future__ import annotations

import csv
import json
import math
import mimetypes
import os
import shutil
import subprocess
import tempfile
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
WEB_ROOT = PROJECT_ROOT / "web"
COMPUTE_SCRIPT = PROJECT_ROOT / "server" / "compute_once.jl"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8080
DEFAULT_G0 = 0.5
DEFAULT_GPRIME0 = 1.0
DEFAULT_MAX_NODES = 80
DEFAULT_MAX_REQUEST_BYTES = 1_048_576


def log(message: str) -> None:
    try:
        print(message, flush=True)
    except OSError:
        pass

    log_file = os.environ.get("SERVER_LOG_FILE")
    if log_file:
        with Path(log_file).open("a", encoding="utf-8") as handle:
            handle.write(message + "\n")


def find_julia() -> str:
    env_value = os.environ.get("JULIA_EXE")
    candidates: list[str | None] = [env_value]

    juliaup_root = Path.home() / ".julia" / "juliaup"
    if juliaup_root.exists():
        candidates.extend(str(path) for path in sorted(juliaup_root.glob("julia-*/bin/julia.exe"), reverse=True))

    candidates.append(shutil.which("julia"))

    for candidate in candidates:
        if candidate and "Microsoft\\WindowsApps" in candidate:
            continue

        if candidate and Path(candidate).exists():
            return str(Path(candidate))

    raise RuntimeError("Cannot find julia.exe. Set JULIA_EXE to the Julia executable path.")


def as_finite_float(value: Any, label: str) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{label} must be a finite number.") from exc

    if not math.isfinite(parsed):
        raise ValueError(f"{label} must be a finite number.")

    return parsed


def as_int(value: Any, label: str) -> int:
    if isinstance(value, bool):
        raise ValueError(f"{label} must be an integer.")

    if isinstance(value, int):
        return value

    if isinstance(value, float) and value.is_integer():
        return int(value)

    raise ValueError(f"{label} must be an integer.")


def as_mu(value: Any, label: str) -> int:
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"∞", "inf", "+inf", "infinity", "+infinity"}:
            return -1

    return as_int(value, label)


def parse_edge_seq(edge_seq_raw: Any) -> tuple[list[list[float]], int]:
    if not isinstance(edge_seq_raw, list) or not edge_seq_raw:
        raise ValueError("edge_seq cannot be empty.")

    edge_seq: list[list[float]] = []
    max_node = 0

    for index, row in enumerate(edge_seq_raw, start=1):
        if not isinstance(row, list) or len(row) != 3:
            raise ValueError(f"edge_seq row {index} must have 3 columns.")

        source = as_int(row[0], f"edge_seq[{index},1]")
        target = as_int(row[1], f"edge_seq[{index},2]")
        weight = as_finite_float(row[2], f"edge_seq[{index},3]")

        if source < 1 or target < 1:
            raise ValueError("node indices must start from 1.")

        if weight < 0.0:
            raise ValueError("edge weights must be non-negative.")

        max_node = max(max_node, source, target)
        edge_seq.append([source, target, weight])

    edge_weights = {(int(source), int(target)): weight for source, target, weight in edge_seq}
    for source, target, weight in edge_seq:
        reverse = edge_weights.get((int(target), int(source)))
        if reverse is None:
            raise ValueError(f"missing reverse edge for {int(source)},{int(target)}.")
        if reverse != weight:
            raise ValueError(f"reverse edge weight differs for {int(source)},{int(target)}.")

    return edge_seq, max_node


def parse_adjacency_matrix(value: Any) -> tuple[list[list[float]], int]:
    if not isinstance(value, list) or not value:
        raise ValueError("adjacency_matrix cannot be empty.")

    node_count = len(value)
    matrix: list[list[float]] = []

    for row_index, row in enumerate(value, start=1):
        if not isinstance(row, list) or len(row) != node_count:
            raise ValueError("adjacency_matrix must be a non-empty square matrix.")

        parsed_row = [
            as_finite_float(cell, f"adjacency_matrix[{row_index},{col_index}]")
            for col_index, cell in enumerate(row, start=1)
        ]

        if any(weight < 0.0 for weight in parsed_row):
            raise ValueError("adjacency_matrix weights must be non-negative.")

        matrix.append(parsed_row)

    for row_index, row in enumerate(matrix, start=1):
        if sum(row) <= 0.0:
            raise ValueError(f"node {row_index} has zero weighted degree.")

    for i in range(node_count):
        for j in range(i + 1, node_count):
            if not math.isclose(matrix[i][j], matrix[j][i], rel_tol=0.0, abs_tol=1e-12):
                raise ValueError("adjacency_matrix must be symmetric for an undirected weighted network.")

    edge_seq: list[list[float]] = []
    for i, row in enumerate(matrix, start=1):
        for j, weight in enumerate(row, start=1):
            if weight != 0.0:
                edge_seq.append([i, j, weight])

    return edge_seq, node_count


def parse_g(payload: dict[str, Any]) -> tuple[float, float]:
    g = payload.get("g")

    if isinstance(g, dict):
        g_type = str(g.get("type", "local")).strip().lower()

        if g_type == "fermi":
            beta = as_finite_float(g.get("beta", 1.0), "g.beta")
            if beta <= 0.0:
                raise ValueError("g.beta must be positive for the Fermi function.")
            return 0.5, beta / 4.0

        if g_type == "local":
            g0 = as_finite_float(g.get("value_at_zero"), "g.value_at_zero")
            gprime0 = as_finite_float(g.get("slope_at_zero"), "g.slope_at_zero")
        else:
            raise ValueError("g.type must be 'fermi' or 'local'.")
    else:
        g0 = as_finite_float(payload.get("g0", DEFAULT_G0), "g0")
        gprime0 = as_finite_float(payload.get("gprime0", DEFAULT_GPRIME0), "gprime0")

    if g0 < 0.0 or g0 > 1.0:
        raise ValueError("g(0) must lie in [0,1].")

    if gprime0 < 0.0:
        raise ValueError("g'(0) must be non-negative.")

    return g0, gprime0


def parse_payload(payload: dict[str, Any]) -> dict[str, Any]:
    if "adjacency_matrix" in payload:
        edge_seq, max_node = parse_adjacency_matrix(payload.get("adjacency_matrix"))
    else:
        edge_seq, max_node = parse_edge_seq(payload.get("edge_seq"))

    max_nodes = int(os.environ.get("MAX_NODES", str(DEFAULT_MAX_NODES)))
    if max_node > max_nodes:
        raise ValueError(f"N = {max_node} exceeds the public demo limit of {max_nodes} nodes.")

    PTE = payload.get("PTE")
    mu = payload.get("mu")

    if not isinstance(PTE, list) or len(PTE) != max_node:
        raise ValueError(f"PTE length must equal N = {max_node}.")

    if not isinstance(mu, list) or len(mu) != max_node:
        raise ValueError(f"mu length must equal N = {max_node}.")

    PTE_values = [as_finite_float(value, f"PTE[{index}]") for index, value in enumerate(PTE, start=1)]
    mu_values = [as_mu(value, f"mu[{index}]") for index, value in enumerate(mu, start=1)]

    if any(value < 0.0 or value > 1.0 for value in PTE_values):
        raise ValueError("PTE values must lie in [0,1].")

    if any(value >= 0 and value > max_node for value in mu_values):
        raise ValueError(f"finite mu values must lie in [0,N], where N = {max_node}.")

    g0, gprime0 = parse_g(payload)
    max_iter_tau = as_int(payload.get("max_iter_tau", 500), "max_iter_tau")
    conv_tol_tau = as_finite_float(payload.get("conv_tol_tau", 1e-10), "conv_tol_tau")

    if max_iter_tau < 1:
        raise ValueError("max_iter_tau must be positive.")

    if conv_tol_tau <= 0.0:
        raise ValueError("conv_tol_tau must be positive.")

    return {
        "edge_seq": edge_seq,
        "PTE": PTE_values,
        "mu": mu_values,
        "g0": g0,
        "gprime0": gprime0,
        "max_iter_tau": max_iter_tau,
        "conv_tol_tau": conv_tol_tau,
    }


def write_inputs(input_dir: Path, payload: dict[str, Any]) -> None:
    with (input_dir / "edge_seq.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerows(payload["edge_seq"])

    for key in ("PTE", "mu"):
        with (input_dir / f"{key}.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            for value in payload[key]:
                writer.writerow([value])

    with (input_dir / "params.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        for key in ("g0", "gprime0", "max_iter_tau", "conv_tol_tau"):
            writer.writerow([key, payload[key]])


def parse_scalar(value: str) -> Any:
    stripped = value.strip()

    if stripped == "true":
        return True

    if stripped == "false":
        return False

    try:
        parsed = float(stripped)
    except ValueError:
        return stripped

    if not math.isfinite(parsed):
        return None

    return parsed


def read_summary(path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {}

    with path.open("r", newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        for row in reader:
            if len(row) != 2:
                continue
            result[row[0]] = parse_scalar(row[1])

    return result


def read_numeric_csv(path: Path) -> list[Any]:
    rows: list[list[float | None]] = []

    with path.open("r", newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        for row in reader:
            if not row:
                continue
            parsed_row = [parse_scalar(value) for value in row]
            rows.append(parsed_row)

    if rows and all(len(row) == 1 for row in rows):
        return [row[0] for row in rows]

    return rows


def compute(payload: dict[str, Any]) -> dict[str, Any]:
    julia_exe = find_julia()
    timeout = int(os.environ.get("COMPUTE_TIMEOUT_SECONDS", "120"))

    with tempfile.TemporaryDirectory(prefix="critical-condition-") as temp_root:
        temp_path = Path(temp_root)
        input_dir = temp_path / "input"
        output_dir = temp_path / "output"
        input_dir.mkdir()
        output_dir.mkdir()

        write_inputs(input_dir, payload)

        env = os.environ.copy()
        env["JULIA_LOAD_PATH"] = "@stdlib"
        env["JULIA_PROJECT"] = ""

        completed = subprocess.run(
            [
                julia_exe,
                "--startup-file=no",
                "--compiled-modules=no",
                str(COMPUTE_SCRIPT),
                str(input_dir),
                str(output_dir),
            ],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
            timeout=timeout,
            check=False,
        )

        if completed.returncode != 0:
            message = completed.stderr.strip() or completed.stdout.strip() or "Julia computation failed."
            raise RuntimeError(message)

        result = read_summary(output_dir / "summary.csv")
        result["pi"] = read_numeric_csv(output_dir / "pi.csv")
        result["PRE"] = read_numeric_csv(output_dir / "PRE.csv")
        return result


def public_result(result: dict[str, Any]) -> dict[str, Any]:
    return {
        "bc_star": result.get("bc_star"),
        "tau_converged": result.get("tau_converged"),
        "tau_err": result.get("tau_err"),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "CriticalConditionServer/0.1"

    def handle(self) -> None:
        try:
            super().handle()
        except Exception:
            log(traceback.format_exc())
            raise

    def end_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        super().end_headers()

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.end_headers()

    def do_GET(self) -> None:
        request_path = self.path.split("?", 1)[0]
        relative = "index.html" if request_path == "/" else request_path.lstrip("/")
        file_path = (WEB_ROOT / relative).resolve()

        if not str(file_path).startswith(str(WEB_ROOT.resolve())) or not file_path.is_file():
            self.send_json({"error": "Not found."}, status=404)
            return

        content_type = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
        if content_type.startswith("text/") or file_path.suffix in {".js", ".css"}:
            content_type = f"{content_type}; charset=utf-8"
        body = file_path.read_bytes()

        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:
        if self.path.split("?", 1)[0] != "/api/compute":
            self.send_json({"error": "Not found."}, status=404)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            max_request_bytes = int(os.environ.get("MAX_REQUEST_BYTES", str(DEFAULT_MAX_REQUEST_BYTES)))
            if length > max_request_bytes:
                raise ValueError(f"Request body exceeds the public demo limit of {max_request_bytes} bytes.")

            raw_body = self.rfile.read(length).decode("utf-8")
            payload = json.loads(raw_body)

            if not isinstance(payload, dict):
                raise ValueError("Request body must be a JSON object.")

            parsed = parse_payload(payload)
            result = compute(parsed)
            self.send_json(public_result(result))
        except ValueError as exc:
            self.send_json({"error": str(exc)}, status=400)
        except subprocess.TimeoutExpired:
            self.send_json({"error": "Computation timed out."}, status=504)
        except Exception as exc:
            self.send_json({"error": str(exc)}, status=500)

    def send_json(self, value: dict[str, Any], status: int = 200) -> None:
        body = json.dumps(value, ensure_ascii=False, allow_nan=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: Any) -> None:
        log(f"{self.address_string()} - {format % args}")


def main() -> None:
    host = os.environ.get("HOST", DEFAULT_HOST)
    port = int(os.environ.get("PORT", str(DEFAULT_PORT)))

    log("Starting critical condition server.")
    julia_exe = find_julia()
    log(f"Using Julia: {julia_exe}")

    server = ThreadingHTTPServer((host, port), Handler)
    log(f"Serving web UI at http://{host}:{port}/")
    log("Press Ctrl+C to stop.")
    server.serve_forever()


if __name__ == "__main__":
    main()
