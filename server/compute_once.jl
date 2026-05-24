using DelimitedFiles

include(joinpath(@__DIR__, "..", "src", "NetworkReciprocityCriticalCondition.jl"))
using .NetworkReciprocityCriticalCondition

length(ARGS) == 2 || error("Usage: compute_once.jl <input_dir> <output_dir>")

input_dir = ARGS[1]
output_dir = ARGS[2]

function read_vector(path::AbstractString, ::Type{T}) where {T}
    data = readdlm(path, ',', Float64)
    return T.(vec(data))
end

function read_params(path::AbstractString)
    params = Dict{String,String}()

    for line in eachline(path)
        isempty(strip(line)) && continue
        parts = split(line, ","; limit=2)
        length(parts) == 2 || error("Invalid parameter row: $line")
        params[strip(parts[1])] = strip(parts[2])
    end

    return params
end

edge_seq = readdlm(joinpath(input_dir, "edge_seq.csv"), ',', Float64)
PTE = read_vector(joinpath(input_dir, "PTE.csv"), Float64)
mu = read_vector(joinpath(input_dir, "mu.csv"), Int)
params = read_params(joinpath(input_dir, "params.csv"))

g0 = parse(Float64, params["g0"])
gprime0 = parse(Float64, params["gprime0"])
max_iter_tau = parse(Int, params["max_iter_tau"])
conv_tol_tau = parse(Float64, params["conv_tol_tau"])

result = compute_bc_heterogeneous(
    edge_seq,
    PTE,
    mu,
    g0,
    gprime0;
    max_iter_tau=max_iter_tau,
    conv_tol_tau=conv_tol_tau,
)

mkpath(output_dir)

open(joinpath(output_dir, "summary.csv"), "w") do io
    println(io, "bc_star,$(result.bc_star)")
    println(io, "zeta_IL_b,$(result.zeta_IL_b)")
    println(io, "zeta_SL_b,$(result.zeta_SL_b)")
    println(io, "zeta_IL_c,$(result.zeta_IL_c)")
    println(io, "zeta_SL_c,$(result.zeta_SL_c)")
    println(io, "numerator,$(result.numerator)")
    println(io, "denominator,$(result.denominator)")
    println(io, "kappa,$(result.kappa)")
    println(io, "tau_converged,$(result.tau_converged)")
    println(io, "tau_err,$(result.tau_err)")
end

writedlm(joinpath(output_dir, "pi.csv"), result.pi, ',')
writedlm(joinpath(output_dir, "PRE.csv"), result.PRE, ',')
writedlm(joinpath(output_dir, "tau_mat.csv"), result.tau_mat, ',')
writedlm(joinpath(output_dir, "tauTE_final.csv"), result.tauTE_final, ',')
