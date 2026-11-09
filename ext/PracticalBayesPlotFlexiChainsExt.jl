module PracticalBayesPlotFlexiChainsExt

# Draws from a FlexiChain (what Turing.jl, PracticalBayes and
# PracticalBayesianRegression return): every parameter, with array-valued
# parameters split into their elements. Extras (sampler statistics) are left
# out.

using PracticalBayesPlot
import PracticalBayesPlot: todraws
using FlexiChains: FlexiChains, FlexiChain, Parameter

function todraws(chain::FlexiChain)
    out = Pair{String,Matrix{Float64}}[]
    for k in FlexiChains.parameters(chain)
        p = k isa Parameter ? k : Parameter(k)   # FlexiChains 0.6 returns keys, 0.7 names
        _push_draws!(out, string(p.name), collect(chain[p]))
    end
    return out
end

_push_draws!(out, name, m::AbstractMatrix{<:Real}) = push!(out, name => Matrix{Float64}(m))
function _push_draws!(out, name, m::AbstractMatrix)
    v = first(m)
    if v isa AbstractArray{<:Real}
        for I in CartesianIndices(v)
            push!(out, "$name[$(join(Tuple(I), ","))]" => Float64[x[I] for x in m])
        end
    elseif v isa Real
        push!(out, name => Matrix{Float64}(m))   # e.g. a Union with Missing
    end
    return out                                   # other values (structs, strings) cannot be plotted
end

end
