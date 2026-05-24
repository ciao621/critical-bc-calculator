using NetworkReciprocityCriticalCondition

edge_seq = [
    1 2 1.0
    2 1 1.0
    2 3 1.0
    3 2 1.0
]

PTE = [0.2, 0.3, 0.4]
mu = [1, 0, 2]
g0 = 0.5
gprime0 = 1.0

result = compute_bc_heterogeneous(edge_seq, PTE, mu, g0, gprime0)

println("bc_star = ", result.bc_star)
println("kappa = ", result.kappa)
println("pi = ", result.pi)
println("tau_converged = ", result.tau_converged)
println("tau_err = ", result.tau_err)
