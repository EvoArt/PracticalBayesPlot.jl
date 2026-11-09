"""
    PracticalBayesPlot

Lightweight plotting for the Bayesian workflow: posterior predictive checks,
effect plots, traces, residuals and intervals. Draws figures as SVG, has no
dependencies, and loads in milliseconds.

The package exports nothing. The API follows Makie's names (`Figure`, `Axis`,
`lines!`, `hist!`, ...), so load it qualified to use it alongside Makie:

```julia
import PracticalBayesPlot as PBP
fig = PBP.Figure()
ax = PBP.Axis(fig[1, 1])
PBP.lines!(ax, 1:10, rand(10))
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
        :wong_colors, :kde, :svg, :save, :preview))
end

include("colors.jl")
include("ticks.jl")
include("types.jl")
include("stats.jl")
include("plots.jl")
include("render.jl")
include("io.jl")
include("precompile.jl")

end
