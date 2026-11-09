module PracticalBayesPlotMCMCChainsExt

# Draws from an MCMCChains.Chains: the parameters section, without the
# sampler's internals.

using PracticalBayesPlot
import PracticalBayesPlot: todraws
using MCMCChains: MCMCChains, Chains

function todraws(chain::Chains)
    all = names(chain)
    data = chain.value.data                       # iterations × names × chains
    return Pair{String,Matrix{Float64}}[string(p) => Matrix{Float64}(data[:, findfirst(==(p), all), :])
                                        for p in names(chain, :parameters)]
end

end
