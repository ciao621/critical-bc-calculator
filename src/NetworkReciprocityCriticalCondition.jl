module NetworkReciprocityCriticalCondition

export pi_heterogeneous
export tau_with_crosstime_heterogeneous
export compute_bc_heterogeneous

include(joinpath(@__DIR__, "..", "Initial program", "Critical condition.jl"))

end
