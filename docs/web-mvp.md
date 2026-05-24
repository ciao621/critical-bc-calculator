# Web MVP

## First User Flow

1. Choose free input or one of the 40-node examples.
2. Paste or edit a symmetric weighted adjacency matrix.
3. Enter `PTE` and decision-mechanism values `mu`.
4. Click compute.
5. Inspect `Critical b/c`, computation convergence, computation error, and the
   visualized network.

## Request Shape

```json
{
  "adjacency_matrix": [[0, 1], [1, 0]],
  "PTE": [0.2, 0.2],
  "mu": [1, -1]
}
```

The server converts `adjacency_matrix` into the bidirectional `edge_seq`
required by the Julia core. The browser accepts `∞` for random trial-and-error
and sends it as negative `mu`, matching the Julia convention for μ_i → ∞.
Finite example `mu` values should lie in `[0,N]`. The main UI does not expose
the response function; the API uses `g(0) = 0.5` and `g'(0) = 1.0` by default.

## Response Shape

```json
{
  "bc_star": 1.0,
  "tau_converged": true,
  "tau_err": 1e-11
}
```

## Local Backend

The first backend uses Python's standard library for HTTP and calls Julia in a
subprocess for the actual model computation. This avoids adding Julia web/JSON
dependencies before the mathematical core is stable.

Start it with:

```powershell
& 'D:\spyder\python.exe' server\compute_server.py
```

Then open:

```text
http://127.0.0.1:8080/
```
