"""
    PracticalBayesPlot

Lightweight plotting for the Bayesian workflow: trace plots, posterior
densities and intervals, and posterior predictive checks, plus the
Makie-style primitives they are built from. Draws figures as SVG, has no
dependencies, and loads in milliseconds.

The package exports nothing. The API follows Makie's names (`Figure`, `Axis`,
`lines!`, `hist!`, ...), so load it qualified to use it alongside Makie:

```julia
import PracticalBayesPlot as PBP
PBP.traceplot((; mu = randn(1000, 4), sigma = exp.(randn(1000, 4))))
```
"""
module PracticalBayesPlot

# The public API. Nothing is exported, because almost every name is also
# exported by Makie; on Julia 1.11 and later these are declared `public`.
@static if VERSION >= v"1.11.0-DEV.469"
    eval(Expr(:public,
        :Figure, :Axis, :Relative, :current_axis,
        :lines!, :lines, :scatter!, :scatter, :stairs!, :stairs, :band!, :band,
        :barplot!, :barplot, :hist!, :hist, :density!, :density, :ecdfplot!, :ecdfplot,
        :rangebars!, :rangebars, :hlines!, :vlines!, :text!,
        :axislegend, :xlims!, :ylims!, :limits!, :colsize!, :rowsize!,
        :traceplot, :densities, :intervals, :intervals!, :ppcheck, :ppcheck!, :todraws,
        :wong_colors, :kde, :svg, :save, :preview))
end

include("colors.jl")
include("ticks.jl")
include("types.jl")
include("stats.jl")
include("plots.jl")
include("bayes.jl")
include("render.jl")
include("io.jl")
include("precompile.jl")

end
