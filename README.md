# PracticalBayesPlot.jl

> **Proof of principle.** This package shows that pure Julia plotting can
> be fast, with very low latency, when it targets a specific, small set of
> plots rather than trying to plot everything.

Small plotting package for Bayesian model checking: posterior predictive
checks, effect plots, trace plots, residuals and interval plots. It is
written in Julia only, has no dependencies, and draws figures as SVG.

It loads in about 40 ms. A first figure, such as a posterior predictive
check with 50 overlaid densities and a histogram, compiles almost nothing
because the package's code is cached at precompile time.

The interface is borrowed from [Makie](https://github.com/MakieOrg/Makie.jl):
the function names (`Figure`, `Axis`, `lines!`, `hist!`, ...), the
`fig[i, j]` layout, the keyword names and the default colour cycle all follow
Makie, so Makie plotting code ports with few changes. Credit for that design
goes to the Makie developers; this package only reimplements a small part of
it.

## Example

```julia
using PracticalBayesPlot

y = randn(300)
yrep = randn(50, 300)              # 50 replicated data sets

fig = Figure(; size = (800, 350))
ax = Axis(fig[1, 1]; xlabel = "y", ylabel = "density")
for s in axes(yrep, 1)
    density!(ax, view(yrep, s, :); color = (:steelblue, 0.25), linewidth = 0.8)
end
density!(ax, y; color = :black, linewidth = 2.5, label = "y")
axislegend(ax)

ax2 = Axis(fig[1, 2]; xlabel = "T = mean")
hist!(ax2, vec(sum(yrep; dims = 2)) ./ 300; bins = 30, color = (:steelblue, 0.4))
vlines!(ax2, sum(y) / 300; linewidth = 3)
colsize!(fig, 1, Relative(0.6))

save("ppcheck.svg", fig)
```

One-call forms make a figure with a single axis:

```julia
fig = hist(randn(1000); bins = 40, axis = (; xlabel = "x"))
lines!(current_axis(), [-2, 2], [0, 100])
```

## Showing figures

- VS Code, Jupyter and Pluto show a `Figure` inline (as SVG).
- In a terminal REPL, displaying a `Figure` opens it in the browser.
  `preview(fig)` does the same from anywhere.
- `save("fig.svg", fig)` writes SVG; `save("fig.html", fig)` writes a page
  holding the SVG. For PNG or PDF, convert the SVG (for example with
  `rsvg-convert` or Inkscape).
- `svg(fig)` returns the SVG as a string.

## What it draws

| Function | Draws |
|:---------|:------|
| `lines!(ax, x, y)` | lines; `NaN` breaks a line |
| `stairs!(ax, x, y; step)` | step lines (`:pre`, `:post`, `:center`) |
| `scatter!(ax, x, y)` | markers: `:circle`, `:rect`, `:diamond`, `:utriangle`, `:dtriangle` |
| `band!(ax, x, lower, upper)` | filled band, e.g. a credible band |
| `barplot!(ax, x, heights)` | bars; `x` may be strings |
| `hist!(ax, data; bins, normalization)` | histogram (`:none`, `:pdf`, `:probability`, `:density`) |
| `density!(ax, data)` | Gaussian kernel density estimate |
| `ecdfplot!(ax, data)` | empirical CDF |
| `rangebars!(ax, pos, low, high; direction)` | intervals, vertical or horizontal |
| `hlines!(ax, ys)`, `vlines!(ax, xs)` | reference lines across the axis |
| `text!(ax, x, y; text)` | text at data coordinates |
| `axislegend(ax, title; position)` | legend of the plots given a `label` |

Each has a one-call form without `!` (except the reference lines, text and
legend), and a form without `ax` that draws into `current_axis()`.

Common keywords: `color`, `alpha`, `linewidth`, `linestyle` (`:solid`,
`:dash`, `:dot`, `:dashdot`), `label`. A colour is a name (`:steelblue`,
`"red"`), a hex string, an `(r, g, b)` tuple with values in 0–1, an integer
index into `wong_colors()`, or `(colour, alpha)`. Without `color`, plots
take the next colour of the axis's cycle (Wong's colour-blind-safe palette,
in Makie's order).

Axis attributes (keywords to `Axis`, or set later as `ax.xlabel = "..."`):
`title`, `xlabel`, `ylabel`, `xticks`, `yticks` (positions, or
`(positions, labels)`), `limits`, `xgridvisible`, `ygridvisible`. Also
`xlims!`, `ylims!`, `limits!`. Layout: `Axis(fig[i, j])`, with ranges to
span cells (`fig[1:2, 1]`); `colsize!` and `rowsize!` set relative sizes.

`PracticalBayesPlot.kde(x, grid)` is the density estimate `density!` uses,
for code that needs the numbers.

## With Makie

The package exports Makie's names, so loading both in one session makes
unqualified calls such as `lines!` ambiguous. Use one per session, or
`import PracticalBayesPlot as PBP` and qualify (`PBP.lines!`).

## Gallery

[examples/pbr_plots.jl](examples/pbr_plots.jl) draws PracticalBayesianRegression's
plots (`pp_check` of every type, `plot_effects` with and without groups and
for categorical predictors, `trace_plot`, `residual_plot`) and a
bayesplot-style interval plot from plain arrays. Write them to
`examples/out/` with

```
julia --project=examples examples/pbr_plots.jl
```

## Not supported

Log axes, colour maps and heatmaps, 3-d plots, and raster output. They are
outside the plots the package is for.
