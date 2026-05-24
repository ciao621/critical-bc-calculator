using SparseArrays
using LinearAlgebra

"""
	pi_heterogeneous(edge_seq, PTE, mu, g0)

Compute the mutation-inclusive reproductive value π for a static weighted network
with heterogeneous individual decision parameters.

Inputs
------
edge_seq:
	Matrix whose first three columns are [i, j, weight].
	The edge list must already be bidirectionally stored.
	That is, if (i, j, w) exists, then (j, i, w) should also exist.

PTE:
	Vector of individual trial-and-error probabilities P_i^TE, length N.

mu:
	Vector of individual TE lengths μ_i, length N.
	If mu[i] < 0, it is treated as μ_i → ∞, so P_i^RE = 0.

g0:
	g(0).

Returns
-------
NamedTuple with fields:
	pi              : reproductive value vector, sum(pi)=1
	kappa           : κ computed from κ = 2/N * sum_i π_i P_i^IL
	kappa_from_eig  : κ computed from the leading eigenvalue of H
	H               : characteristic matrix H
	P               : row-stochastic random-walk matrix p_ij
	PRE             : P_i^RE
	PIL             : P_i^IL
	residual        : norm(H*pi + kappa*pi)
"""
function pi_heterogeneous(
    edge_seq::Matrix{<:Real},
    PTE::Vector{Float64},
    mu::Vector{Int},
    g0::Float64,
)
    # ------------------------------------------------------------
    # 1. Basic dimensions and checks
    # ------------------------------------------------------------
    N = Int(maximum(edge_seq[:, 1:2]))

    length(PTE) == N || error("length(PTE) must equal N = $N.")
    length(mu) == N || error("length(mu) must equal N = $N.")

    any(PTE .< 0.0) && error("Some PTE values are negative.")
    any(PTE .> 1.0) && error("Some PTE values are larger than 1.")
    g0 < 0.0 && error("g0 must be non-negative.")
    g0 > 1.0 && error("g0 should not exceed 1.")

    # ------------------------------------------------------------
    # 2. Build weighted adjacency matrix W
    #    edge_seq is assumed to be bidirectionally stored.
    # ------------------------------------------------------------
    rows = Int.(edge_seq[:, 1])
    cols = Int.(edge_seq[:, 2])
    vals = Float64.(edge_seq[:, 3])

    W = sparse(rows, cols, vals, N, N)

    # Weighted degree: w_i = sum_j w_ij
    deg = vec(sum(W, dims=2))

    if any(deg .== 0.0)
        bad_nodes = findall(deg .== 0.0)
        error("The network has isolated nodes: $bad_nodes")
    end

    # ------------------------------------------------------------
    # 3. Row-stochastic random-walk matrix P, where P[i,j] = p_ij
    # ------------------------------------------------------------
    P = spdiagm(0 => 1.0 ./ deg) * W

    # ------------------------------------------------------------
    # 4. Compute P_i^RE and P_i^IL
    # ------------------------------------------------------------
    PRE = zeros(Float64, N)
    PIL = zeros(Float64, N)

    for i in 1:N
        if mu[i] < 0
            # Use mu < 0 as a proxy for μ_i → ∞.
            PRE[i] = 0.0
            chi_i = 1.0
        else
            PRE[i] = PTE[i] * (1.0 - 1.0 / N)^mu[i]
            chi_i = mu[i] > 0 ? 1.0 : -1.0
        end

        PIL[i] = PTE[i] + g0 * PRE[i] * chi_i
    end

    # ------------------------------------------------------------
    # 5. Construct H
    #
    # H_ij = (1 - P_j^TE) p_ji / N,                      i ≠ j
    # H_ii = [(1 - P_i^TE)p_ii - (1 - P_i^TE)∑_k p_ik
    #         - 2P_i^IL] / N
    #
    # Since ∑_k p_ik = 1, this is:
    #
    # H = [(P' - I)D - 2diag(PIL)] / N,
    # where D = diag(1 - P_i^TE).
    # ------------------------------------------------------------
    D = spdiagm(0 => 1.0 .- PTE)
    I_N = spdiagm(0 => ones(Float64, N))

    H = ((transpose(P) - I_N) * D - 2.0 * spdiagm(0 => PIL)) / N

    # ------------------------------------------------------------
    # 6. Compute the spectral-bound eigenvector
    #
    # H is a Metzler matrix. We take the eigenvector associated with
    # the eigenvalue having the largest real part.
    # ------------------------------------------------------------
    F = eigen(Matrix(H))

    max_idx = argmax(real.(F.values))
    lambda_H = real(F.values[max_idx])

    pi_raw = real.(F.vectors[:, max_idx])

    # Choose orientation so that the vector has positive total mass.
    if sum(pi_raw) < 0.0
        pi_raw .= -pi_raw
    end

    pi = pi_raw ./ sum(pi_raw)

    # κ from eigenvalue and from κ = 2M0
    kappa_from_eig = -lambda_H
    kappa = (2.0 / N) * dot(pi, PIL)

    residual = norm(Matrix(H) * pi + kappa * pi)

    return (
        pi=pi,
        kappa=kappa,
        kappa_from_eig=kappa_from_eig,
        H=H,
        P=P,
        PRE=PRE,
        PIL=PIL,
        residual=residual,
    )
end



using LinearAlgebra
using SparseArrays

"""
	tau_with_crosstime_heterogeneous(edge_seq, PTE, mu, g0;
		max_iter=300,
		conv_tol=1e-10,
		verbose=false)

Compute neutral IIS probabilities τ_ij and backward cross-time IIS probabilities
τ_(i←j)^Δt for a static weighted network with heterogeneous individual decision parameters.

Model:
	Static weighted network.
	edge_seq is assumed to be bidirectionally stored.
	Individual-level PTE[i] and mu[i].

Inputs
------
edge_seq:
	Matrix whose first three columns are [i, j, weight].
	The edge list must already be bidirectionally stored.

PTE:
	Vector of individual trial-and-error probabilities P_i^TE, length N.

mu:
	Vector of individual TE lengths μ_i, length N.
	If mu[i] < 0, it is treated as μ_i → ∞, so P_i^RE = 0 and no delayed reflection is computed.

g0:
	g(0).

Keyword arguments
-----------------
max_iter:
	Maximum number of fixed-point iterations.

conv_tol:
	Convergence tolerance for fixed-point iteration.

verbose:
	Whether to print iteration errors.

Internal tauTE layout
---------------------
	tauTE[target, origin, dt+1] = τ_(origin ← target)^dt.

That is:
	tauTE[j, i, dt+1] = τ_(i←j)^dt.

Outputs
-------
NamedTuple with fields:
	tau_mat:
		N×N matrix, tau_mat[i,j] = τ_ij.

	tauTE_final:
		N×N matrix, tauTE_final[i,j] = τ_(i←j)^(μ_i).
		If μ_i = 0, tauTE_final[i,j] = τ_ij.
		If μ_i < 0, tauTE_final[i,j] = 0 because P_i^RE = 0.

	tauTE_hist:
		N×N×(max_mu+1) array with internal layout:
		tauTE_hist[j,i,dt+1] = τ_(i←j)^dt.

	P:
		Row-stochastic random-walk matrix p_ij.

	PRE:
		Vector P_i^RE.

	chi_g:
		Vector χ_i^g.

	PRE_cond_table:
		Matrix where PRE_cond_table[j,dt+1] = P_j^{dt|RE}.

	converged:
		Whether fixed-point iteration converged.

	err:
		Final fixed-point error.
"""
function tau_with_crosstime_heterogeneous(
    edge_seq::AbstractMatrix{<:Real},
    PTE::Vector{Float64},
    mu::Vector{Int},
    g0::Float64;
    max_iter::Int=300,
    conv_tol::Float64=1e-10,
    verbose::Bool=false,
)
    # ================================================================
    # 0. Basic dimensions and checks
    # ================================================================
    N = Int(maximum(edge_seq[:, 1:2]))

    length(PTE) == N || error("length(PTE) must equal N = $N.")
    length(mu) == N || error("length(mu) must equal N = $N.")
    all((0.0 .<= PTE) .& (PTE .<= 1.0)) || error("PTE must lie in [0,1].")
    0.0 <= g0 <= 1.0 || error("g0 must lie in [0,1].")
    N > 1 || error("N must be greater than 1.")

    # ================================================================
    # 1. Build row-stochastic random-walk matrix P
    #    edge_seq is assumed to be bidirectionally stored.
    # ================================================================
    rows = Int.(edge_seq[:, 1])
    cols = Int.(edge_seq[:, 2])
    vals = Float64.(edge_seq[:, 3])

    W = sparse(rows, cols, vals, N, N)

    deg = vec(sum(W, dims=2))

    if any(deg .== 0.0)
        bad_nodes = findall(deg .== 0.0)
        error("The network has isolated nodes: $bad_nodes")
    end

    P = spdiagm(0 => 1.0 ./ deg) * W

    # Row neighbor lists for fast sparse row iteration.
    P_row_cols = [Int[] for _ in 1:N]
    P_row_vals = [Float64[] for _ in 1:N]

    IrowP, JcolP, VvalP = findnz(P)

    for idx in eachindex(VvalP)
        i = IrowP[idx]
        j = JcolP[idx]
        v = VvalP[idx]
        push!(P_row_cols[i], j)
        push!(P_row_vals[i], v)
    end

    # ================================================================
    # 2. PRE and chi_g
    # ================================================================
    PRE = zeros(Float64, N)
    chi_g = zeros(Float64, N)

    for i in 1:N
        if mu[i] < 0
            # μ_i → ∞ proxy: no reflection.
            PRE[i] = 0.0
            chi_g[i] = 0.0
        else
            PRE[i] = PTE[i] * (1.0 - 1.0 / N)^mu[i]
            chi_g[i] = (mu[i] == 0) ? g0 : 0.0
        end
    end

    finite_mu = [m for m in mu if m >= 0]
    max_mu = isempty(finite_mu) ? 0 : maximum(finite_mu)

    # ================================================================
    # 3. Precompute P_j^{dt|RE}
    #
    # PRE_cond_table[j, dt+1] = P_j^{dt|RE}, dt = 0,1,...,max_mu.
    #
    # P_j^{dt|RE} =
    #   (N-1)/N * PTE_j * (1-1/N)^(mu_j-dt-1) * (1-1/(N-1))^dt,  mu_j > dt
    #   0,                                                                  mu_j = dt
    #   PTE_j * (1-1/(N-1))^mu_j,                                           mu_j < dt
    # ================================================================
    pow_N = [(1.0 - 1.0 / N)^k for k in 0:max_mu]
    pow_Nm1 = [(1.0 - 1.0 / (N - 1.0))^k for k in 0:max_mu]

    PRE_cond_table = zeros(Float64, N, max_mu + 1)

    for j in 1:N
        m = mu[j]

        for dt in 0:max_mu
            if m < 0
                PRE_cond_table[j, dt+1] = 0.0
            elseif m > dt
                # exponent of pow_N is m-dt-1, stored at index m-dt
                PRE_cond_table[j, dt+1] =
                    ((N - 1.0) / N) *
                    PTE[j] *
                    pow_N[m-dt] *
                    pow_Nm1[dt+1]
            elseif m == dt
                PRE_cond_table[j, dt+1] = 0.0
            else
                # m < dt, including m = 0 when dt ≥ 1
                PRE_cond_table[j, dt+1] =
                    PTE[j] * pow_Nm1[m+1]
            end
        end
    end

    # ================================================================
    # 4. Indexing for τ_ij unknowns, i ≠ j
    # ================================================================
    tau_index = zeros(Int, N, N)
    n_tau_unknown = 0

    for i in 1:N, j in 1:N
        if i != j
            n_tau_unknown += 1
            tau_index[i, j] = n_tau_unknown
        end
    end

    function unpack_tau_full!(
        tau_mat_out::Matrix{Float64},
        x::Vector{Float64},
    )
        @inbounds for j in 1:N
            for i in 1:N
                if i == j
                    tau_mat_out[i, j] = 1.0
                else
                    tau_mat_out[i, j] = x[tau_index[i, j]]
                end
            end
        end

        return nothing
    end

    # ================================================================
    # 5. Build sparse linear system for τ given tauTE
    #
    # Eq. (16):
    #
    # τ_ij =
    # 1/(2-M_i-M_j) [
    #     P_i^TE(1-χ_i^g) + P_j^TE(1-χ_j^g)
    #   + Σ_k ((1-P_i^TE)p_ik τ_kj + (1-P_j^TE)p_jk τ_ik)
    #   + g0(P_i^RE τ_(i←j)^μ_i + P_j^RE τ_(j←i)^μ_j)
    # ]
    #
    # We construct:
    #     A * τ_unknown = b_base + dynamic cross-time terms.
    # ================================================================
    Irow = Int[]
    Jcol = Int[]
    Vval = Float64[]
    b_base = zeros(Float64, n_tau_unknown)

    function add_lhs!(row::Int, col::Int, coeff::Float64)
        push!(Irow, row)
        push!(Jcol, col)
        push!(Vval, coeff)
        return nothing
    end

    function add_rhs_tau_term!(row::Int, coeff::Float64, a::Int, b::Int)
        # RHS contains coeff * τ_ab.
        # Move to LHS: -coeff * τ_ab.
        if a == b
            b_base[row] += coeff
        else
            add_lhs!(row, tau_index[a, b], -coeff)
        end

        return nothing
    end

    # dynamic_terms stores terms of the form:
    # b[row] += coeff * τ_(origin←target)^mu_origin.
    #
    # Internal tauTE layout:
    # tauTE[target, origin, d_index] = τ_(origin←target)^dt.
    dynamic_terms = Tuple{Int,Float64,Int,Int,Int}[]
    # tuple = (row, coeff, origin, target, d_index)

    row = 0

    for i in 1:N, j in 1:N
        i == j && continue
        row += 1

        Mi = PTE[i] * (2.0 * chi_g[i] - 1.0) - g0 * PRE[i]
        Mj = PTE[j] * (2.0 * chi_g[j] - 1.0) - g0 * PRE[j]

        denom = 2.0 - Mi - Mj

        # LHS main term: denom * τ_ij
        add_lhs!(row, tau_index[i, j], denom)

        # Constant terms from immediate TE reversal.
        b_base[row] += PTE[i] * (1.0 - chi_g[i])
        b_base[row] += PTE[j] * (1.0 - chi_g[j])

        # Social-learning term for i:
        # Σ_k (1-P_i^TE)p_ik τ_kj
        ci = 1.0 - PTE[i]

        cols_i = P_row_cols[i]
        vals_i = P_row_vals[i]

        for idx in eachindex(vals_i)
            k = cols_i[idx]
            p = vals_i[idx]
            add_rhs_tau_term!(row, ci * p, k, j)
        end

        # Social-learning term for j:
        # Σ_k (1-P_j^TE)p_jk τ_ik
        cj = 1.0 - PTE[j]

        cols_j = P_row_cols[j]
        vals_j = P_row_vals[j]

        for idx in eachindex(vals_j)
            k = cols_j[idx]
            p = vals_j[idx]
            add_rhs_tau_term!(row, cj * p, i, k)
        end

        # Reflection term from i:
        # g0 * PRE[i] * τ_(i←j)^μ_i
        coeff_i = g0 * PRE[i]

        if mu[i] == 0
            # τ_(i←j)^0 = τ_ij
            add_rhs_tau_term!(row, coeff_i, i, j)
        elseif mu[i] > 0
            d_index = mu[i] + 1
            push!(dynamic_terms, (row, coeff_i, i, j, d_index))
        end

        # Reflection term from j:
        # g0 * PRE[j] * τ_(j←i)^μ_j.
        #
        # If μ_j = 0, then τ_(j←i)^0 = τ_ij, not τ_ji.
        coeff_j = g0 * PRE[j]

        if mu[j] == 0
            add_rhs_tau_term!(row, coeff_j, i, j)
        elseif mu[j] > 0
            d_index = mu[j] + 1
            push!(dynamic_terms, (row, coeff_j, j, i, d_index))
        end
    end

    A_mat = sparse(Irow, Jcol, Vval, n_tau_unknown, n_tau_unknown)
    F_mat = lu(A_mat)

    # Preallocated vectors for zero-allocation solve.
    b_vec = similar(b_base)
    x_vec = zeros(Float64, n_tau_unknown)

    function solve_tau_given_tauTE!(
        tau_mat_out::Matrix{Float64},
        tauTE_cur::Array{Float64,3},
    )
        b_vec .= b_base

        @inbounds for (r, coeff, origin, target, d_index) in dynamic_terms
            # tauTE[target, origin, d_index] = τ_(origin←target)^dt
            b_vec[r] += coeff * tauTE_cur[target, origin, d_index]
        end

        ldiv!(x_vec, F_mat, b_vec)

        unpack_tau_full!(tau_mat_out, x_vec)

        return nothing
    end

    # ================================================================
    # 6. Helpers for cross-time IIS computation
    # ================================================================
    function final_cross_tau(
        origin::Int,
        target::Int,
        tau_mat::Matrix{Float64},
        tauTE_old::Array{Float64,3},
    )
        if mu[origin] == 0
            return tau_mat[origin, target]
        elseif mu[origin] > 0
            return tauTE_old[target, origin, mu[origin]+1]
        else
            return 0.0
        end
    end

    function reflection_source_tau(
        origin_j::Int,
        focal_i::Int,
        dt::Int,
        tauTE_new::Array{Float64,3},
        tauTE_old::Array{Float64,3},
    )
        mj = mu[origin_j]

        if mj < 0
            return 0.0
        elseif mj > dt
            # τ_(j←i)^(μ_j-Δt)
            return tauTE_old[focal_i, origin_j, mj-dt+1]
        elseif mj == dt
            # Excluded under strict asynchronous updating.
            # The corresponding coefficient P_j^{dt|RE} is zero.
            return 0.0
        elseif mj == 0
            # τ_(i←j)^Δt
            return tauTE_new[origin_j, focal_i, dt+1]
        else
            # 0 < μ_j < Δt:
            # τ_(i←j)^(Δt-μ_j)
            return tauTE_new[origin_j, focal_i, dt-mj+1]
        end
    end

    # ================================================================
    # 7. Compute all cross-time IIS histories from τ and old tauTE
    #
    # Internal layout:
    # tauTE[target, origin, dt+1] = τ_(origin←target)^dt.
    #
    # For μ_i = 0:
    # tauTE[j,i,1] = τ_ij by convention.
    # ================================================================
    function compute_tauTE!(
        tauTE_new::Array{Float64,3},
        tau_mat::Matrix{Float64},
        tauTE_old::Array{Float64,3},
    )
        fill!(tauTE_new, 0.0)

        # μ_i = 0 convention: τ_(i←j)^0 = τ_ij.
        for i in 1:N
            if mu[i] == 0
                @inbounds for j in 1:N
                    tauTE_new[j, i, 1] = tau_mat[i, j]
                end
            end
        end

        max_mu == 0 && return nothing

        for i in 1:N
            mi = mu[i]

            mi <= 0 && continue

            # --------------------------------------------------------
            # Initialization at Δt = 1.
            # --------------------------------------------------------
            @inbounds for j in 1:N
                if j == i
                    tauTE_new[j, i, 2] = 0.0
                else
                    p0 = PRE_cond_table[j, 1]
                    source = final_cross_tau(j, i, tau_mat, tauTE_old)

                    tauTE_new[j, i, 2] =
                        tau_mat[i, j] * (1.0 - g0 * p0 / (N - 1.0)) +
                        source * (g0 * p0 / (N - 1.0))
                end
            end

            # --------------------------------------------------------
            # Recursion for Δt = 1,2,...,μ_i-1.
            # --------------------------------------------------------
            if mi > 1
                for dt in 1:(mi-1)
                    @inbounds for j in 1:N
                        if j == i
                            tauTE_new[j, i, dt+2] = 0.0
                            continue
                        end

                        p_re_dt = PRE_cond_table[j, dt+1]
                        tau_re = reflection_source_tau(j, i, dt, tauTE_new, tauTE_old)

                        Mj_CIIS =
                            N - 2.0 +
                            PTE[j] * (2.0 * chi_g[j] - 1.0) -
                            g0 * p_re_dt

                        social_sum = 0.0

                        cols_j = P_row_cols[j]
                        vals_j = P_row_vals[j]

                        for idx in eachindex(vals_j)
                            k = cols_j[idx]
                            pjk = vals_j[idx]

                            # If k == i, τ_(i←i)^dt = 0.
                            if k != i
                                social_sum += pjk * tauTE_new[k, i, dt+1]
                            end
                        end

                        tauTE_new[j, i, dt+2] =
                            (
                                PTE[j] * (1.0 - chi_g[j]) +
                                g0 * p_re_dt * tau_re +
                                Mj_CIIS * tauTE_new[j, i, dt+1] +
                                (1.0 - PTE[j]) * social_sum
                            ) / (N - 1.0)
                    end
                end
            end
        end

        return nothing
    end

    # ================================================================
    # 8. Zero-allocation error check
    # ================================================================
    function max_abs_diff(A, B)
        err = 0.0

        @inbounds for idx in eachindex(A, B)
            d = abs(A[idx] - B[idx])
            if d > err
                err = d
            end
        end

        return err
    end

    # ================================================================
    # 9. Fixed-point iteration
    # ================================================================
    tau_mat = fill(0.5, N, N)

    for i in 1:N
        tau_mat[i, i] = 1.0
    end

    tau_mat_new = similar(tau_mat)

    # Internal layout:
    # tauTE[target, origin, dt+1] = τ_(origin←target)^dt.
    tauTE_cur = zeros(Float64, N, N, max_mu + 1)
    tauTE_new = zeros(Float64, N, N, max_mu + 1)

    # Initial guess for cross-time IIS.
    for i in 1:N
        if mu[i] == 0
            @inbounds for j in 1:N
                tauTE_cur[j, i, 1] = tau_mat[i, j]
            end
        elseif mu[i] > 0
            for dt in 1:mu[i]
                @inbounds for j in 1:N
                    tauTE_cur[j, i, dt+1] = (i == j) ? 0.0 : tau_mat[i, j]
                end
            end
        end
    end

    converged = false
    err = Inf

    for it in 1:max_iter
        solve_tau_given_tauTE!(tau_mat_new, tauTE_cur)
        compute_tauTE!(tauTE_new, tau_mat_new, tauTE_cur)

        err_tau = max_abs_diff(tau_mat_new, tau_mat)
        err_te = max_abs_diff(tauTE_new, tauTE_cur)
        err = max(err_tau, err_te)

        if verbose
            println("iter=$it, err_tau=$err_tau, err_tauTE=$err_te, err=$err")
        end

        tau_mat .= tau_mat_new
        tauTE_cur .= tauTE_new

        if err < conv_tol
            converged = true
            verbose && println("Converged at iteration $it.")
            break
        end
    end

    if !converged && verbose
        println("Warning: fixed-point iteration did not converge within max_iter=$max_iter, err=$err.")
    end

    # ================================================================
    # 10. Final cross-time IIS τ_(i←j)^(μ_i)
    #
    # Output layout:
    # tauTE_final[i,j] = τ_(i←j)^(μ_i).
    # ================================================================
    tauTE_final = zeros(Float64, N, N)

    for i in 1:N
        if mu[i] == 0
            @inbounds for j in 1:N
                tauTE_final[i, j] = tau_mat[i, j]
            end
        elseif mu[i] > 0
            @inbounds for j in 1:N
                tauTE_final[i, j] = tauTE_cur[j, i, mu[i]+1]
            end
        else
            # μ_i → ∞ proxy: PRE_i = 0, so this value is not used.
            @inbounds for j in 1:N
                tauTE_final[i, j] = 0.0
            end
        end
    end

    return (
        tau_mat=tau_mat,
        tauTE_final=tauTE_final,
        tauTE_hist=tauTE_cur,
        P=P,
        PRE=PRE,
        chi_g=chi_g,
        PRE_cond_table=PRE_cond_table,
        converged=converged,
        err=err,
    )
end



using LinearAlgebra
using SparseArrays

"""
	compute_bc_heterogeneous(edge_seq, PTE, mu, g0, gprime0;
		max_iter_tau = 500,
		conv_tol_tau = 1e-10,
		verbose_tau = false)

Compute the critical benefit-to-cost ratio (b/c)^* for the static-network
heterogeneous-decision model.

Inputs
------
edge_seq:
	Matrix whose first three columns are [i, j, weight].
	The edge list must already be bidirectionally stored.

PTE:
	Vector of individual trial-and-error probabilities P_i^TE, length N.

mu:
	Vector of individual TE lengths μ_i, length N.
	If mu[i] < 0, it is treated as μ_i → ∞:
		PRE[i] = 0,
		χ_i^IL = 1,
	so it contributes no reflection term and no aspiration-like μ=0 term.

g0:
	g(0).

gprime0:
	g'(0).

Keyword arguments
-----------------
max_iter_tau:
	Maximum number of fixed-point iterations for IIS/cross-time IIS.

conv_tol_tau:
	Convergence tolerance for IIS/cross-time IIS fixed-point iteration.

verbose_tau:
	Whether to print convergence information for IIS/cross-time IIS.

Outputs
-------
NamedTuple with fields:
	bc_star
	zeta_IL_b
	zeta_SL_b
	zeta_IL_c
	zeta_SL_c
	pi
	kappa
	tau_mat
	tauTE_final
	tau_converged
	tau_err
"""
function compute_bc_heterogeneous(
    edge_seq::AbstractMatrix{<:Real},
    PTE::Vector{Float64},
    mu::Vector{Int},
    g0::Float64,
    gprime0::Float64;
    max_iter_tau::Int=500,
    conv_tol_tau::Float64=1e-10,
    verbose_tau::Bool=false,
)
    # ================================================================
    # 1. Basic dimensions and checks
    # ================================================================
    N = Int(maximum(edge_seq[:, 1:2]))

    length(PTE) == N || error("length(PTE) must equal N = $N.")
    length(mu) == N || error("length(mu) must equal N = $N.")
    all((0.0 .<= PTE) .& (PTE .<= 1.0)) || error("PTE must lie in [0,1].")
    0.0 <= g0 <= 1.0 || error("g0 must lie in [0,1].")

    # ================================================================
    # 2. Reproductive value π and κ
    # ================================================================
    pi_result = pi_heterogeneous(edge_seq, PTE, mu, g0)

    π = pi_result.pi
    κ = pi_result.kappa
    PRE = pi_result.PRE

    # κ = 0 is the degenerate case. The critical condition involving
    # division by κ is not valid in that singular limit.
    if κ == 0.0
        @warn "κ = 0. This is the degenerate case; the weak-selection critical condition is singular."
    end

    # ================================================================
    # 3. IIS and cross-time IIS probabilities
    # ================================================================
    tau_result = tau_with_crosstime_heterogeneous(
        edge_seq,
        PTE,
        mu,
        g0;
        max_iter=max_iter_tau,
        conv_tol=conv_tol_tau,
        verbose=verbose_tau,
    )

    τ = tau_result.tau_mat
    τTE = tau_result.tauTE_final

    # Row-stochastic random-walk matrix p_ij.
    # Use the one returned by the IIS solver to avoid rebuilding it.
    P = Matrix(tau_result.P)

    # ================================================================
    # 4. χ_i^IL
    #
    # χ_i^IL = 1 if μ_i > 0.
    # χ_i^IL = 0 if μ_i = 0.
    #
    # If μ_i < 0 is used as μ_i → ∞ in code, set χ_i^IL = 1.
    # Since PRE_i = 0, it contributes no delayed reflection term.
    # ================================================================
    χIL = zeros(Float64, N)

    for i in 1:N
        χIL[i] = (mu[i] == 0) ? 0.0 : 1.0
    end

    # ================================================================
    # 5. ζ_IL^b
    #
    # ζ_IL^b =
    # g'(0) Σ_i π_i [
    #     2χ_i^IL P_i^RE Σ_j p_ij(τ_ij - τ_(i←j)^μ_i)
    #   + (1-χ_i^IL) P_i^TE Σ_j p_ij(2τ_ij - 1)
    # ]
    # ================================================================
    zeta_IL_b = 0.0

    @inbounds for i in 1:N
        s_delayed = 0.0
        s_asp = 0.0

        for j in 1:N
            pij = P[i, j]
            pij == 0.0 && continue

            s_delayed += pij * (τ[i, j] - τTE[i, j])
            s_asp += pij * (2.0 * τ[i, j] - 1.0)
        end

        zeta_IL_b += gprime0 * π[i] * (
                         2.0 * χIL[i] * PRE[i] * s_delayed +
                         (1.0 - χIL[i]) * PTE[i] * s_asp
                     )
    end

    # ================================================================
    # 6. ζ_IL^c
    #
    # ζ_IL^c =
    # g'(0) Σ_i π_i [
    #     2χ_i^IL P_i^RE
    #   + (1-χ_i^IL) P_i^TE
    # ]
    # ================================================================
    zeta_IL_c = 0.0

    @inbounds for i in 1:N
        zeta_IL_c += gprime0 * π[i] * (
                         2.0 * χIL[i] * PRE[i] +
                         (1.0 - χIL[i]) * PTE[i]
                     )
    end

    # ================================================================
    # 7. ζ_SL^b
    #
    # ζ_SL^b =
    # Σ_{i,j,l} π_i(1-P_i^TE)p_ij
    #   (p_jl - Σ_k p_ik p_kl) τ_jl
    #
    # Efficient form:
    #   P2[i,l] = Σ_k p_ik p_kl
    #   A[j]    = Σ_l p_jl τ_jl
    #   B[i,j]  = Σ_l P2[i,l] τ_jl
    #           = (P2 * τ')[i,j]
    # ================================================================
    zeta_SL_b = 0.0

    P2 = P * P
    A = vec(sum(P .* τ, dims=2))
    B = P2 * transpose(τ)

    @inbounds for i in 1:N
        coeff_i = π[i] * (1.0 - PTE[i])
        coeff_i == 0.0 && continue

        s = 0.0

        for j in 1:N
            pij = P[i, j]
            pij == 0.0 && continue

            s += pij * (A[j] - B[i, j])
        end

        zeta_SL_b += coeff_i * s
    end

    # ================================================================
    # 8. ζ_SL^c
    #
    # ζ_SL^c =
    # Σ_{i,j,l} π_i(1-P_i^TE)p_ij
    #   (p_jl τ_jj - Σ_k p_ik p_kl τ_jk)
    #
    # Since τ_jj = 1 and Σ_l p_jl = 1, the first part becomes 1.
    #
    # Efficient form:
    #   C[i,j] = Σ_k p_ik τ_jk = (P * τ')[i,j]
    #   ζ_SL^c = Σ_i π_i(1-P_i^TE) Σ_j p_ij(1 - C[i,j])
    # ================================================================
    zeta_SL_c = 0.0

    C = P * transpose(τ)

    @inbounds for i in 1:N
        coeff_i = π[i] * (1.0 - PTE[i])
        coeff_i == 0.0 && continue

        s = 0.0

        for j in 1:N
            pij = P[i, j]
            pij == 0.0 && continue

            s += pij * (1.0 - C[i, j])
        end

        zeta_SL_c += coeff_i * s
    end

    # ================================================================
    # 9. Critical benefit-to-cost ratio
    #
    # Cooperation is favored when:
    # b(ζ_IL^b + ζ_SL^b) > c(ζ_IL^c + ζ_SL^c).
    #
    # Therefore:
    # (b/c)^* = (ζ_IL^c + ζ_SL^c) / (ζ_IL^b + ζ_SL^b).
    # ================================================================
    denom = zeta_IL_b + zeta_SL_b
    numer = zeta_IL_c + zeta_SL_c

    bc_star = denom == 0.0 ? NaN : numer / denom

    return (
        bc_star=bc_star,
        zeta_IL_b=zeta_IL_b,
        zeta_SL_b=zeta_SL_b,
        zeta_IL_c=zeta_IL_c,
        zeta_SL_c=zeta_SL_c,
        numerator=numer,
        denominator=denom,
        pi=π,
        kappa=κ,
        PRE=PRE,
        tau_mat=τ,
        tauTE_final=τTE,
        tau_converged=tau_result.converged,
        tau_err=tau_result.err,
    )
end



