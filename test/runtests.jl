using LinearAlgebra
using Test
using NetworkReciprocityCriticalCondition

@testset "critical condition core" begin
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

    pi_result = pi_heterogeneous(edge_seq, PTE, mu, g0)

    @test isapprox(sum(pi_result.pi), 1.0; atol=1e-10)
    @test pi_result.kappa >= 0.0
    @test pi_result.residual < 1e-8
    @test all(isapprox.(vec(sum(pi_result.P, dims=2)), 1.0; atol=1e-12))

    tau_result = tau_with_crosstime_heterogeneous(edge_seq, PTE, mu, g0)

    @test tau_result.converged
    @test tau_result.err < 1e-8
    @test all(isapprox.(diag(tau_result.tau_mat), 1.0; atol=1e-12))

    bc_result = compute_bc_heterogeneous(edge_seq, PTE, mu, g0, gprime0)

    @test isfinite(bc_result.bc_star)
    @test bc_result.tau_converged
    @test bc_result.tau_err < 1e-8

    random_trial_result = compute_bc_heterogeneous(edge_seq, PTE, [1, -1, 2], g0, gprime0)

    @test isfinite(random_trial_result.bc_star)
    @test random_trial_result.tau_converged
end

@testset "input validation" begin
    edge_seq = [
        1 2 1.0
        2 1 1.0
    ]

    @test_throws ErrorException pi_heterogeneous(edge_seq, [-0.1, 0.2], [1, 1], 0.5)
    @test_throws ErrorException pi_heterogeneous(edge_seq, [0.1, 1.2], [1, 1], 0.5)
    @test_throws ErrorException pi_heterogeneous(edge_seq, [0.1, 0.2], [1, 1], -0.1)

    edge_with_isolate = [
        1 2 1.0
        2 1 1.0
        3 3 0.0
    ]

    @test_throws ErrorException pi_heterogeneous(edge_with_isolate, [0.1, 0.2, 0.3], [1, 1, 1], 0.5)
end
