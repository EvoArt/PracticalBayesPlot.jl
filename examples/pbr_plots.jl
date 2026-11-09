# The figures PracticalBayesianRegression draws (pp_check, plot_effects,
# trace_plot, residual_plot), written with PracticalBayesPlot from plain
# arrays. They follow the package's Makie extension line for line, so they
# show what a PracticalBayesPlot extension for it would look like.
#
# Run as a script to write the gallery to examples/out/:
#     julia --project=examples examples/pbr_plots.jl

# The package exports nothing; bring the names used here into scope.
import PracticalBayesPlot as PBP
using PracticalBayesPlot: Figure, Axis, Relative, lines!, scatter!, stairs!, band!,
    barplot!, hist!, density!, rangebars!, hlines!, vlines!, text!, axislegend,
    xlims!, ylims!, limits!, colsize!, rowsize!, wong_colors, svg, save
using Random

const YCOL = :black
const REPCOL = (:steelblue, 0.25)

mean(x) = sum(x) / length(x)
median(x) = PBP._quantile_sorted(sort(collect(Float64, x)), 0.5)
quantile(x, p) = PBP._quantile_sorted(sort(collect(Float64, x)), Float64(p))

function density_grid(y, yrep; n=200)
    lo = min(minimum(y), quantile(vec(yrep), 0.005))
    hi = max(maximum(y), quantile(vec(yrep), 0.995))
    return collect(range(lo, hi; length=n))
end

ecdf(x, grid) = [count(<=(g), x) / length(x) for g in grid]

"""
    pp_check_fig(y, yrep; type=:dens_overlay, stat=mean, xlabel="y")

`y`: observed response; `yrep`: replicated data sets, one per row.
"""
function pp_check_fig(y, yrep; type::Symbol=:dens_overlay, stat=mean, xlabel="y")
    fig = Figure(; size=(600, 400))
    ax = Axis(fig[1, 1]; xlabel)
    if type === :dens_overlay
        grid = density_grid(y, yrep)
        for s in axes(yrep, 1)
            lines!(ax, grid, PBP.kde(view(yrep, s, :), grid); color=REPCOL, linewidth=0.8,
                   label=s == 1 ? "y_rep" : "")
        end
        lines!(ax, grid, PBP.kde(y, grid); color=YCOL, linewidth=2.5, label="y")
        ax.ylabel = "density"
        axislegend(ax)
    elseif type === :ecdf_overlay
        grid = density_grid(y, yrep; n=400)
        for s in axes(yrep, 1)
            stairs!(ax, grid, ecdf(view(yrep, s, :), grid); color=REPCOL, step=:post)
        end
        stairs!(ax, grid, ecdf(y, grid); color=YCOL, linewidth=2.5, step=:post)
        ax.ylabel = "ECDF"
    elseif type === :hist
        hist!(ax, vec(yrep); normalization=:pdf, color=REPCOL, bins=40)
        hist!(ax, y; normalization=:pdf, color=(:white, 0.0), strokecolor=YCOL, strokewidth=1.5, bins=40)
    elseif type === :stat
        t = [stat(view(yrep, s, :)) for s in axes(yrep, 1)]
        hist!(ax, t; color=REPCOL, bins=30, label="T(y_rep)")
        vlines!(ax, [stat(y)]; color=YCOL, linewidth=3, label="T(y)")
        ax.xlabel = "T = $(nameof(stat))"
        axislegend(ax)
    elseif type === :bars
        ks = sort(unique(vcat(y, vec(yrep))))
        obs = [count(==(k), y) for k in ks]
        reps = [[count(==(k), view(yrep, s, :)) for s in axes(yrep, 1)] for k in ks]
        barplot!(ax, ks, obs; color=(:steelblue, 0.6), label="y")
        rangebars!(ax, ks, quantile.(reps, 0.05), quantile.(reps, 0.95); color=YCOL)
        scatter!(ax, ks, median.(reps); color=YCOL, label="y_rep")
        ax.ylabel = "count"
        axislegend(ax)
    else
        throw(ArgumentError("unknown pp_check type `$type`"))
    end
    return fig
end

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

"""
    trace_fig(draws)

`draws`: pairs `name => matrix` (iterations x chains). Trace on the left,
per-chain density on the right.
"""
function trace_fig(draws)
    nv = length(draws)
    fig = Figure(; size=(800, 170 * nv))
    for (k, (v, x)) in enumerate(draws)
        ax = Axis(fig[k, 1]; ylabel=v, xlabel=k == nv ? "iteration" : "")
        for c in axes(x, 2)
            lines!(ax, view(x, :, c); color=(wong_colors()[mod1(c, 7)], 0.7), linewidth=0.6)
        end
        ax2 = Axis(fig[k, 2]; xlabel=k == nv ? "value" : "")
        g = collect(range(minimum(x), maximum(x); length=200))
        for c in axes(x, 2)
            lines!(ax2, g, PBP.kde(view(x, :, c), g); color=wong_colors()[mod1(c, 7)])
        end
    end
    colsize!(fig, 1, Relative(0.7))
    return fig
end

function residual_fig(fitted, resid)
    fig = Figure(; size=(600, 400))
    ax = Axis(fig[1, 1]; xlabel="fitted (posterior mean)", ylabel="residual")
    scatter!(ax, fitted, resid; color=(:steelblue, 0.5), markersize=5)
    hlines!(ax, [0.0]; color=:black, linestyle=:dash)
    return fig
end

"""
    intervals_fig(names, draws)

Posterior medians with 50% and 90% intervals, one row per parameter
(bayesplot's mcmc_intervals).
"""
function intervals_fig(names, draws)
    fig = Figure(; size=(500, 60 + 40 * length(names)))
    ax = Axis(fig[1, 1]; xlabel="value", ygridvisible=false)
    q(p) = [quantile(d, p) for d in draws]
    vlines!(ax, 0.0; color=:gray, linestyle=:dot)
    rangebars!(ax, names, q(0.05), q(0.95); direction=:x, color=:steelblue, linewidth=1.5)
    rangebars!(ax, names, q(0.25), q(0.75); direction=:x, color=:steelblue, linewidth=4.5)
    scatter!(ax, q(0.5), names; color=:white, strokecolor=:steelblue, strokewidth=2, markersize=9)
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
        "pp_dens_overlay" => pp_check_fig(y, yrep),
        "pp_ecdf_overlay" => pp_check_fig(y, yrep; type=:ecdf_overlay),
        "pp_hist" => pp_check_fig(y, yrep; type=:hist),
        "pp_stat" => pp_check_fig(y, yrep; type=:stat),
        "pp_bars" => pp_check_fig(ycount, yrepcount; type=:bars),
        "effects" => effects_fig(ce1),
        "effects_by" => effects_fig(ce2),
        "effects_categorical" => effects_fig(ce3),
        "trace" => trace_fig(draws),
        "residuals" => residual_fig(fitted, randn(rng, N) .* 0.5),
        "intervals" => intervals_fig(first.(draws), [vec(last(d)) for d in draws]),
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
