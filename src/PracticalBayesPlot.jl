"""
    PracticalBayesPlot

Small plotting package for Bayesian model checking: posterior predictive
checks, effect plots, traces and residuals. Draws figures as SVG, has no
dependencies, and loads in milliseconds.

The API follows Makie's names (`Figure`, `Axis`, `lines!`, `hist!`, ...), so
Makie plotting code ports with few changes.
"""
module PracticalBayesPlot

export Figure, Axis, Relative, current_axis,
       lines!, lines, scatter!, scatter, stairs!, stairs, band!, band,
       barplot!, barplot, hist!, hist, density!, density, ecdfplot!, ecdfplot,
       rangebars!, rangebars, hlines!, vlines!, text!,
       axislegend, xlims!, ylims!, limits!, colsize!, rowsize!,
       wong_colors, svg, save, preview

include("colors.jl")
include("ticks.jl")
include("types.jl")
include("stats.jl")
include("plots.jl")
include("render.jl")
include("io.jl")
include("precompile.jl")

end
