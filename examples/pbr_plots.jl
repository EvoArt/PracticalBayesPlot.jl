# A gallery of the figures PracticalBayesianRegression draws with
# PracticalBayesPlot (its default plotting backend): posterior predictive
# checks, conditional effects, traces, residuals and intervals, here from
# simulated arrays in the shapes the package produces. The predictive
# checks, traces and intervals are PracticalBayesPlot's own functions; the
# effects and residual plots show figures built from the primitives.
#
# Run as a script to write the gallery to examples/out/:
#     julia --project=examples examples/pbr_plots.jl

import PracticalBayesPlot as PBP
using PracticalBayesPlot: Figure, Axis, band!, lines!, scatter!, rangebars!, hlines!, axislegend,
    wong_colors, save
using Random

"""
    effects_fig(ce)

`ce`: a NamedTuple like PracticalBayesianRegression's `conditional_effects`
result, `(x, [by,] estimate, lower, upper)`.
"""
function effects_fig(ce::NamedTuple)
    names = keys(ce)
    xname = names[1]
    by = length(names) == 5 ? names[2] : nothing
    fig = Figure(; size=(600, 400))
    ax = Axis(fig[1, 1]; xlabel=string(xname), ylabel="estimate")
    groups = by === nothing ? [nothing] : unique(ce[by])
    for (k, gv) in enumerate(groups)
        sel = gv === nothing ? eachindex(ce.estimate) : findall(==(gv), ce[by])
        x = ce[xname][sel]
        col = wong_colors()[mod1(k, 7)]
        if eltype(x) <: Real
            band!(ax, x, ce.lower[sel], ce.upper[sel]; color=(col, 0.25))
            lines!(ax, x, ce.estimate[sel]; color=col, linewidth=2, label=gv === nothing ? "" : string(gv))
        else
            rangebars!(ax, string.(x), ce.lower[sel], ce.upper[sel]; color=col, whiskerwidth=8)
            scatter!(ax, string.(x), ce.estimate[sel]; color=col, markersize=10)
        end
    end
    by === nothing || axislegend(ax, string(by); position=:lt)
    return fig
end

function residual_fig(fitted, resid)
    fig = Figure(; size=(600, 400))
    ax = Axis(fig[1, 1]; xlabel="fitted (posterior mean)", ylabel="residual")
    scatter!(ax, fitted, resid; color=(:steelblue, 0.5), markersize=5)
    hlines!(ax, [0.0]; color=:black, linestyle=:dash)
    return fig
end

# --- synthetic data in the shapes PracticalBayesianRegression produces ---------

function gallery(rng=Xoshiro(1))
    N = 200
    y = 2 .+ 0.8 .* randn(rng, N) .+ 0.3 .* randn(rng, N) .^ 2
    yrep = 2.1 .+ 0.85 .* randn(rng, 50, N)
    ycount = Float64.(rand(rng, 0:6, N))
    yrepcount = Float64.(rand(rng, 0:6, 50, N))
    xs = collect(range(-2, 2; length=40))
    ce1 = (x=xs, estimate=0.5 .* xs, lower=0.5 .* xs .- 0.3, upper=0.5 .* xs .+ 0.3)
    ce2 = (x=[xs; xs], group=[fill("a", 40); fill("b", 40)], estimate=[0.5 .* xs; 1 .- 0.3 .* xs],
           lower=[0.5 .* xs .- 0.3; 0.7 .- 0.3 .* xs], upper=[0.5 .* xs .+ 0.3; 1.3 .- 0.3 .* xs])
    ce3 = (treatment=["control", "low", "high"], estimate=[1.0, 1.4, 2.1], lower=[0.7, 1.1, 1.6],
           upper=[1.3, 1.7, 2.6])
    draws = ["b_Intercept" => 2 .+ 0.1 .* randn(rng, 1000, 4), "b_x" => 0.5 .+ 0.05 .* randn(rng, 1000, 4),
             "sigma" => 0.8 .+ 0.04 .* randn(rng, 1000, 4)]
    fitted = 2 .+ 0.5 .* randn(rng, N)
    return [
        "pp_dens_overlay" => PBP.ppcheck(y, yrep),
        "pp_ecdf_overlay" => PBP.ppcheck(y, yrep; type=:ecdf_overlay),
        "pp_hist" => PBP.ppcheck(y, yrep; type=:hist),
        "pp_stat" => PBP.ppcheck(y, yrep; type=:stat),
        "pp_bars" => PBP.ppcheck(ycount, yrepcount; type=:bars),
        "effects" => effects_fig(ce1),
        "effects_by" => effects_fig(ce2),
        "effects_categorical" => effects_fig(ce3),
        "trace" => PBP.traceplot(draws),
        "densities" => PBP.densities(draws),
        "residuals" => residual_fig(fitted, randn(rng, N) .* 0.5),
        "intervals" => PBP.intervals(draws),
    ]
end
if abspath(PROGRAM_FILE) == @__FILE__
    out = joinpath(@__DIR__, "out")
    mkpath(out)
    figs = gallery()
    for (name, fig) in figs
        save(joinpath(out, name * ".svg"), fig)
    end
    open(joinpath(out, "index.html"), "w") do io
        println(io, "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>PracticalBayesPlot gallery</title></head>",
                "<body style=\"background:#fff;font-family:sans-serif\">")
        for (name, _) in figs
            println(io, "<figure style=\"display:inline-block;margin:8px\"><img src=\"$name.svg\"><figcaption>$name</figcaption></figure>")
        end
        println(io, "</body></html>")
    end
    println("wrote $(length(figs)) figures to $out")
end
