# Plot objects and the functions that add them to an axis.
#
# Load time and time to first plot: the public functions are thin keyword
# wrappers marked `@nospecialize` (which also covers their keyword bodies),
# so a new combination of argument or keyword types does not recompile them.
# They convert their inputs to Vector{Float64}, Paint and String and hand
# over to internal functions with concrete signatures, which are compiled
# once, during precompilation.

struct LinesPlot <: PlotObj
    x::Vector{Float64}
    y::Vector{Float64}
    color::Paint
    linewidth::Float64
    dash::String
    label::String
end

struct ScatterPlot <: PlotObj
    x::Vector{Float64}
    y::Vector{Float64}
    color::Paint
    markersize::Float64
    marker::Symbol
    strokecolor::Paint
    strokewidth::Float64
    label::String
end

struct BandPlot <: PlotObj
    x::Vector{Float64}
    lo::Vector{Float64}
    hi::Vector{Float64}
    color::Paint
    label::String
end

struct BarsPlot <: PlotObj
    x::Vector{Float64}
    h::Vector{Float64}
    width::Vector{Float64}
    fillto::Float64
    color::Paint
    strokecolor::Paint
    strokewidth::Float64
    label::String
end

struct RangeBarsPlot <: PlotObj
    pos::Vector{Float64}
    lo::Vector{Float64}
    hi::Vector{Float64}
    horizontal::Bool       # direction = :x
    color::Paint
    linewidth::Float64
    whiskerwidth::Float64
    label::String
end

struct RefLinesPlot <: PlotObj
    vals::Vector{Float64}
    horizontal::Bool
    color::Paint
    linewidth::Float64
    dash::String
    label::String
end

struct TextPlot <: PlotObj
    x::Vector{Float64}
    y::Vector{Float64}
    text::Vector{String}
    latex::Vector{String}      # empty, or one LaTeX form per text ("" = none)
    color::Paint
    fontsize::Float64
    dataspace::Bool            # fontsize in data units (markerspace = :data)
    halign::Symbol
    valign::Symbol
end

# polygons, one per run of finite points
struct PolyPlot <: PlotObj
    x::Vector{Float64}
    y::Vector{Float64}
    color::Paint
    strokecolor::Paint
    strokewidth::Float64
    dash::String
    label::String
end

struct HeatmapPlot <: PlotObj
    xe::Vector{Float64}        # cell edges
    ye::Vector{Float64}
    fills::Matrix{Paint}
end

_label(p::PlotObj) = p.label
_label(::TextPlot) = ""
_label(::HeatmapPlot) = ""

# --- input handling -------------------------------------------------------------

_f64(x::Real) = Float64[x]
_f64(x::Vector{Float64}) = copy(x)
_f64(x) = Float64[Float64(v) for v in x]

_isnumeric(x) = x isa Real || x isa AbstractVector{<:Real} || all(v -> v isa Real, x)

# positions along an axis; non-numeric values become categories at 1, 2, ...
function _pos(ax::Axis, x, dim::Symbol)::Vector{Float64}
    _isnumeric(x) && return _f64(x)
    return _catpos(dim === :x ? ax.xcategories : ax.ycategories, String[string(v) for v in x])
end

function _catpos(cats::Vector{String}, labels::Vector{String})
    out = Vector{Float64}(undef, length(labels))
    for (i, s) in enumerate(labels)
        k = findfirst(==(s), cats)
        if k === nothing
            push!(cats, s)
            k = length(cats)
        end
        out[i] = k
    end
    return out
end

_vec(x)::Vector{Float64} = _f64(x)
_str(x)::String = string(x)

function _samelen(names::String, a::Vector{Float64}, b::Vector{Float64}, c::Vector{Float64}=a)
    (length(a) == length(b) == length(c)) ||
        throw(DimensionMismatch("$names must have the same length; got lengths $(length(a)), $(length(b))" *
                                (c === a ? "" : ", $(length(c))")))
    return length(a)
end

function _color!(ax::Axis, @nospecialize(color), alpha::Float64, defaultalpha::Float64=1.0)::Paint
    if color === nothing
        ax.cycle += 1
        return paint(ax.cycle, alpha * defaultalpha)
    end
    return paint(color, alpha * 1.0)
end
_paint(c)::Paint = paint(c, 1.0)

function _dash(ls::Symbol, lw::Float64)
    s = max(lw, 1.0)
    pat = ls === :solid ? () :
          ls === :dash ? (4s, 2.5s) :
          ls === :dot ? (s, 2s) :
          ls === :dashdot ? (4s, 2s, s, 2s) :
          throw(ArgumentError("linestyle must be :solid, :dash, :dot or :dashdot; got :$ls"))
    return join((string(round(v; digits=1)) for v in pat), ",")
end
_dash(::Nothing, lw::Float64) = ""
_dash(ls, lw::Float64) = throw(ArgumentError("linestyle must be :solid, :dash, :dot or :dashdot; got $(repr(ls))"))

_push!(ax::Axis, p::PlotObj) = (push!(ax.plots, p); p)

const MARKERS = (:circle, :rect, :diamond, :utriangle, :dtriangle)

# --- plot functions ------------------------------------------------------------------

"""
    lines!(ax, x, y; color, alpha=1, linewidth=1.5, linestyle=:solid, label="")
    lines!(ax, y)

Connect the points `(x[i], y[i])` with straight lines. `NaN`s break the line.
`linestyle` is `:solid`, `:dash`, `:dot` or `:dashdot`.

Colours: a name (`:steelblue`, `"red"`), a hex string, an `(r, g, b)` tuple,
an integer index into [`wong_colors`](@ref), or `(colour, alpha)`. Without
`color`, each plot takes the next colour of the axis's cycle.
"""
function lines!(ax::Axis, x, y; color=nothing, alpha=1.0, linewidth=1.5, linestyle=:solid, label="")
    @nospecialize
    return _lines!(ax, _pos(ax, x, :x), _vec(y), _color!(ax, color, Float64(alpha)), Float64(linewidth),
                   linestyle, _str(label))
end
function lines!(ax::Axis, y; kwargs...)
    @nospecialize
    return lines!(ax, 1:length(y), y; kwargs...)
end

function _lines!(ax::Axis, x::Vector{Float64}, y::Vector{Float64}, c::Paint, lw::Float64, ls, label::String)
    _samelen("x and y", x, y)
    return _push!(ax, LinesPlot(x, y, c, lw, _dash(ls, lw), label))
end

"""
    stairs!(ax, x, y; step=:pre, kwargs...)

A step function through the points. `step = :pre` puts each horizontal
segment before (left of) its point, `:post` after it, `:center` centred on
it. Other keywords as [`lines!`](@ref).
"""
function stairs!(ax::Axis, x, y; step=:pre, kwargs...)
    @nospecialize
    px, py = _steps(_pos(ax, x, :x), _vec(y), step)
    return lines!(ax, px, py; kwargs...)
end
function stairs!(ax::Axis, y; kwargs...)
    @nospecialize
    return stairs!(ax, 1:length(y), y; kwargs...)
end

function _steps(xs::Vector{Float64}, ys::Vector{Float64}, step::Symbol)
    step in (:pre, :post, :center) || throw(ArgumentError("step must be :pre, :post or :center; got :$step"))
    n = _samelen("x and y", xs, ys)
    n == 0 && return xs, ys
    px = Float64[xs[1]]
    py = Float64[ys[1]]
    for i in 2:n
        if step === :pre
            push!(px, xs[i-1], xs[i]); push!(py, ys[i], ys[i])
        elseif step === :post
            push!(px, xs[i], xs[i]); push!(py, ys[i-1], ys[i])
        else
            m = (xs[i-1] + xs[i]) / 2
            push!(px, m, m, xs[i]); push!(py, ys[i-1], ys[i], ys[i])
        end
    end
    return px, py
end

"""
    scatter!(ax, x, y; color, alpha=1, markersize=8, marker=:circle,
             strokecolor=:black, strokewidth=0, label="")

Markers at the points. `markersize` is the diameter in pixels; `marker` is
`:circle`, `:rect`, `:diamond`, `:utriangle` or `:dtriangle`. `x` and `y`
may hold strings, which become categories.
"""
function scatter!(ax::Axis, x, y; color=nothing, alpha=1.0, markersize=8, marker=:circle,
                  strokecolor=:black, strokewidth=0, label="")
    @nospecialize
    return _scatter!(ax, _pos(ax, x, :x), _pos(ax, y, :y), _color!(ax, color, Float64(alpha)), Float64(markersize),
                     marker, _paint(strokecolor), Float64(strokewidth), _str(label))
end
function scatter!(ax::Axis, y; kwargs...)
    @nospecialize
    return scatter!(ax, 1:length(y), y; kwargs...)
end

function _scatter!(ax::Axis, x::Vector{Float64}, y::Vector{Float64}, c::Paint, ms::Float64, marker::Symbol,
                   sc::Paint, sw::Float64, label::String)
    marker in MARKERS || throw(ArgumentError("marker must be one of $(join(MARKERS, ", ")); got :$marker"))
    _samelen("x and y", x, y)
    return _push!(ax, ScatterPlot(x, y, c, ms, marker, sc, sw, label))
end

"""
    band!(ax, x, lower, upper; color, alpha=1, label="")

Fill the region between `lower` and `upper` along `x`, e.g. a credible band.
Without `color`, the axis's next cycle colour at 30% opacity is used.
"""
function band!(ax::Axis, x, lower, upper; color=nothing, alpha=1.0, label="")
    @nospecialize
    return _band!(ax, _pos(ax, x, :x), _vec(lower), _vec(upper), _color!(ax, color, Float64(alpha), 0.3), _str(label))
end

function _band!(ax::Axis, x::Vector{Float64}, lo::Vector{Float64}, hi::Vector{Float64}, c::Paint, label::String)
    _samelen("x, lower and upper", x, lo, hi)
    return _push!(ax, BandPlot(x, lo, hi, c, label))
end

"""
    barplot!(ax, x, heights; width=nothing, gap=0.2, fillto=0, color, alpha=1,
             strokecolor=:black, strokewidth=0, label="")

Vertical bars of `heights` centred on `x`. `x` may hold strings, which
become categories at 1, 2, ... with their names as tick labels. Without
`width`, bars are `1 - gap` of the smallest spacing between `x` values.
"""
function barplot!(ax::Axis, x, heights; width=nothing, gap=0.2, fillto=0.0, color=nothing, alpha=1.0,
                  strokecolor=:black, strokewidth=0, label="")
    @nospecialize
    xs = _pos(ax, x, :x)
    ws = width === nothing ? Float64[] : width isa Real ? fill(Float64(width), length(xs)) : _vec(width)
    return _barplot!(ax, xs, _vec(heights), ws, Float64(gap), Float64(fillto), _color!(ax, color, Float64(alpha)),
                     _paint(strokecolor), Float64(strokewidth), _str(label))
end
function barplot!(ax::Axis, heights; kwargs...)
    @nospecialize
    return barplot!(ax, 1:length(heights), heights; kwargs...)
end

function _barplot!(ax::Axis, x::Vector{Float64}, h::Vector{Float64}, w::Vector{Float64}, gap::Float64,
                   fillto::Float64, c::Paint, sc::Paint, sw::Float64, label::String)
    n = _samelen("x and heights", x, h)
    if isempty(w)
        u = sort!(unique(x))
        sp = length(u) > 1 ? minimum(diff(u)) : 1.0
        w = fill((1 - gap) * sp, n)
    end
    _samelen("x and width", x, w)
    return _push!(ax, BarsPlot(x, h, w, fillto, c, sc, sw, label))
end

"""
    hist!(ax, data; bins=15, normalization=:none, color, alpha=1,
          strokecolor=:black, strokewidth=0, label="")

Histogram of the finite values in `data`. `bins` is a number of equal-width
bins or a vector of edges. `normalization`: `:none` (counts), `:pdf` (area
1), `:probability` (heights sum to 1) or `:density` (counts / bin width).
For outline-only bars, pass `color = :transparent` and a `strokewidth`.
"""
function hist!(ax::Axis, data; bins=15, normalization=:none, color=nothing, alpha=1.0,
               strokecolor=:black, strokewidth=0, label="")
    @nospecialize
    v = filter(isfinite, _vec(data))
    isempty(v) && throw(ArgumentError("hist! needs at least one finite value"))
    edges = bins isa Integer ? _edges(v, Int(bins)) : _edges(v, _vec(bins))
    return _hist!(ax, v, edges, normalization, _color!(ax, color, Float64(alpha)), _paint(strokecolor),
                  Float64(strokewidth), _str(label))
end

function _hist!(ax::Axis, v::Vector{Float64}, edges::Vector{Float64}, normalization::Symbol, c::Paint,
                sc::Paint, sw::Float64, label::String)
    cnt = _bincounts(v, edges)
    w = diff(edges)
    n = length(v)
    h = normalization === :none ? cnt :
        normalization === :pdf ? cnt ./ (n .* w) :
        normalization === :probability ? cnt ./ n :
        normalization === :density ? cnt ./ w :
        throw(ArgumentError("normalization must be :none, :pdf, :probability or :density; got :$normalization"))
    centres = (edges[1:end-1] .+ edges[2:end]) ./ 2
    return _push!(ax, BarsPlot(centres, h, w, 0.0, c, sc, sw, label))
end

"""
    density!(ax, data; npoints=200, bandwidth=nothing, kwargs...)

Gaussian kernel density estimate of `data`, drawn as a line over the range
of the data extended by three bandwidths. `bandwidth` defaults to
Silverman's rule. Other keywords as [`lines!`](@ref).
"""
function density!(ax::Axis, data; npoints=200, bandwidth=nothing, kwargs...)
    @nospecialize
    g, d = _density(_vec(data), Int(npoints), bandwidth === nothing ? NaN : Float64(bandwidth))
    return lines!(ax, g, d; kwargs...)
end

function _density(x::Vector{Float64}, npoints::Int, h::Float64)
    v = filter(isfinite, x)
    length(v) >= 2 || throw(ArgumentError("density! needs at least two finite values"))
    isnan(h) && (h = bandwidth(v))
    lo, hi = extrema(v)
    g = collect(range(lo - 3h, hi + 3h; length=npoints))
    return g, kde(v, g, h)
end

"""
    ecdfplot!(ax, data; kwargs...)

Empirical cumulative distribution function of the finite values in `data`,
as a step line. Keywords as [`lines!`](@ref).
"""
function ecdfplot!(ax::Axis, data; kwargs...)
    @nospecialize
    x, y = _ecdf(_vec(data))
    return stairs!(ax, x, y; step=:post, kwargs...)
end

function _ecdf(x::Vector{Float64})
    v = sort!(filter(isfinite, x))
    isempty(v) && throw(ArgumentError("ecdfplot! needs at least one finite value"))
    n = length(v)
    return [v[1]; v], [0.0; (1:n) ./ n]
end

"""
    rangebars!(ax, pos, low, high; direction=:y, color=:black, alpha=1,
               linewidth=1.5, whiskerwidth=0, label="")

Line segments from `low` to `high` at each position, e.g. credible
intervals. `direction = :y` draws vertical bars at x = `pos`; `:x` draws
horizontal bars at y = `pos`. Positions may be strings (categories).
`whiskerwidth` is the width of the end caps in pixels.
"""
function rangebars!(ax::Axis, pos, low, high; direction=:y, color=:black, alpha=1.0, linewidth=1.5,
                    whiskerwidth=0, label="")
    @nospecialize
    direction in (:x, :y) || throw(ArgumentError("direction must be :x or :y; got $(repr(direction))"))
    p = _pos(ax, pos, direction === :y ? :x : :y)
    return _rangebars!(ax, p, _vec(low), _vec(high), direction === :x, _color!(ax, color, Float64(alpha)),
                       Float64(linewidth), Float64(whiskerwidth), _str(label))
end

function _rangebars!(ax::Axis, p::Vector{Float64}, lo::Vector{Float64}, hi::Vector{Float64}, horiz::Bool,
                     c::Paint, lw::Float64, ww::Float64, label::String)
    _samelen("positions, low and high", p, lo, hi)
    return _push!(ax, RangeBarsPlot(p, lo, hi, horiz, c, lw, ww, label))
end

"""
    hlines!(ax, ys; color=:black, alpha=1, linewidth=1, linestyle=:solid, label="")

Horizontal reference lines across the whole axis. They do not affect the
automatic x limits. See also [`vlines!`](@ref).
"""
function hlines!(ax::Axis, ys; color=:black, alpha=1.0, linewidth=1.0, linestyle=:solid, label="")
    @nospecialize
    return _reflines!(ax, _vec(ys), true, _color!(ax, color, Float64(alpha)), Float64(linewidth), linestyle, _str(label))
end

"""
    vlines!(ax, xs; color=:black, alpha=1, linewidth=1, linestyle=:solid, label="")

Vertical reference lines across the whole axis; see [`hlines!`](@ref).
"""
function vlines!(ax::Axis, xs; color=:black, alpha=1.0, linewidth=1.0, linestyle=:solid, label="")
    @nospecialize
    return _reflines!(ax, _vec(xs), false, _color!(ax, color, Float64(alpha)), Float64(linewidth), linestyle, _str(label))
end

function _reflines!(ax::Axis, v::Vector{Float64}, horiz::Bool, c::Paint, lw::Float64, ls, label::String)
    return _push!(ax, RefLinesPlot(v, horiz, c, lw, _dash(ls, lw), label))
end

"""
    text!(ax, x, y; text, color=:black, fontsize=12, align=(:left, :bottom),
          markerspace=:pixel, latex=nothing)

Text at data coordinates. `x`, `y` and `text` may be single values or
vectors of equal length. `align` is (`:left`/`:center`/`:right`,
`:bottom`/`:center`/`:top`).

- `markerspace = :data` measures `fontsize` in data units (of x), so text
  scales with the plot, as in Makie; `:pixel` (default) measures it in pixels.
- `latex`: a LaTeX (math mode) form of each text, without the `\$`s. The
  [`tikz`](@ref) output typesets it with LaTeX; the SVG output shows `text`.
"""
function text!(ax::Axis, x, y; text, color=:black, fontsize=12, align=(:left, :bottom),
               markerspace=:pixel, latex=nothing)
    @nospecialize
    ts = text isa AbstractString ? String[text] : String[string(t) for t in text]
    lx = latex === nothing ? String[] :
         latex isa AbstractString ? String[latex] : String[t === nothing ? "" : string(t) for t in latex]
    markerspace in (:pixel, :data) || throw(ArgumentError("markerspace must be :pixel or :data; got $(repr(markerspace))"))
    return _text!(ax, _vec(x), _vec(y), ts, lx, _paint(color), Float64(fontsize), markerspace === :data,
                  align[1], align[2])
end

function _text!(ax::Axis, x::Vector{Float64}, y::Vector{Float64}, ts::Vector{String}, lx::Vector{String},
                c::Paint, fs::Float64, data::Bool, ha::Symbol, va::Symbol)
    (length(x) == length(y) == length(ts)) ||
        throw(DimensionMismatch("x, y and text must have the same length"))
    isempty(lx) || length(lx) == length(ts) ||
        throw(DimensionMismatch("latex must have one entry per text"))
    ha in (:left, :center, :right) && va in (:bottom, :center, :top) ||
        throw(ArgumentError("align must be (:left|:center|:right, :bottom|:center|:top)"))
    return _push!(ax, TextPlot(x, y, ts, lx, c, fs, data, ha, va))
end

"""
    poly!(ax, x, y; color, alpha=1, strokecolor=:black, strokewidth=0,
          linestyle=:solid, label="")
    poly!(ax, points; kwargs...)
    poly!(ax, [points1, points2, ...]; kwargs...)

Filled polygons. Give the corners as vectors `x` and `y`, as a vector of
points (`(x, y)` tuples, 2-vectors or Makie `Point2f`s), or as a vector of
such vectors for several polygons in one style. Polygons are closed
automatically; `NaN` in `x` and `y` separates polygons. `color =
:transparent` with a `strokewidth` draws outlines only.
"""
function poly!(ax::Axis, x, y; color=nothing, alpha=1.0, strokecolor=:black, strokewidth=0,
               linestyle=:solid, label="")
    @nospecialize
    sw = Float64(strokewidth)
    return _poly!(ax, _vec(x), _vec(y), _color!(ax, color, Float64(alpha)), _paint(strokecolor), sw,
                  _dash(linestyle, sw), _str(label))
end
function poly!(ax::Axis, pts; kwargs...)
    @nospecialize
    x, y = _polypoints(pts)
    return poly!(ax, x, y; kwargs...)
end

# points, or a vector of polygons (each a vector of points), as x and y with
# NaN between polygons
function _polypoints(@nospecialize(pts))
    x = Float64[]
    y = Float64[]
    isempty(pts) && return x, y
    p1 = first(pts)
    if first(p1) isa Real
        for p in pts
            push!(x, Float64(p[1])); push!(y, Float64(p[2]))
        end
    else
        for poly in pts
            isempty(x) || (push!(x, NaN); push!(y, NaN))
            for p in poly
                push!(x, Float64(p[1])); push!(y, Float64(p[2]))
            end
        end
    end
    return x, y
end

function _poly!(ax::Axis, x::Vector{Float64}, y::Vector{Float64}, c::Paint, sc::Paint, sw::Float64,
                dash::String, label::String)
    _samelen("x and y", x, y)
    return _push!(ax, PolyPlot(x, y, c, sc, sw, dash, label))
end

"""
    heatmap!(ax, x, y, values; colormap=:viridis, colorrange=nothing, alpha=1)
    heatmap!(ax, values; kwargs...)

A grid of coloured cells, `values[i, j]` at column `x[i]` and row `y[j]`.
`x` and `y` are cell centres (one per row/column of `values`) or cell edges
(one more). Without them, cells are centred on 1, 2, .... `colormap` is
`:viridis`, `:cividis`, `:grays`, `:blues`, `:reds` or a vector of colours;
`colorrange = (low, high)` fixes the values at its ends (default: the
extrema of the finite values). `NaN` cells are left empty.
"""
function heatmap!(ax::Axis, x, y, values::AbstractMatrix; colormap=:viridis, colorrange=nothing, alpha=1.0)
    @nospecialize
    v = Matrix{Float64}(values)
    cr = colorrange === nothing ? (NaN, NaN) : (Float64(colorrange[1]), Float64(colorrange[2]))
    return _heatmap!(ax, _vec(x), _vec(y), v, _stops(colormap), cr, Float64(alpha))
end
function heatmap!(ax::Axis, values::AbstractMatrix; kwargs...)
    @nospecialize
    return heatmap!(ax, 1:size(values, 1), 1:size(values, 2), values; kwargs...)
end

function _edges_of(c::Vector{Float64}, n::Int, name::String)
    length(c) == n + 1 && return c
    length(c) == n || throw(DimensionMismatch("$name must have one entry per cell ($n) or one per edge ($(n + 1)); got $(length(c))"))
    n == 1 && return [c[1] - 0.5, c[1] + 0.5]
    e = Vector{Float64}(undef, n + 1)
    for i in 2:n
        e[i] = (c[i-1] + c[i]) / 2
    end
    e[1] = c[1] - (e[2] - c[1])
    e[n+1] = c[n] + (c[n] - e[n])
    return e
end

function _heatmap!(ax::Axis, x::Vector{Float64}, y::Vector{Float64}, v::Matrix{Float64},
                   stops::Vector{NTuple{3,Float64}}, cr::Tuple{Float64,Float64}, alpha::Float64)
    nx, ny = size(v)
    xe = _edges_of(x, nx, "x")
    ye = _edges_of(y, ny, "y")
    lo, hi = cr
    if isnan(lo) || isnan(hi)
        fin = filter(isfinite, vec(v))
        a, b = isempty(fin) ? (0.0, 1.0) : extrema(fin)
        isnan(lo) && (lo = a)
        isnan(hi) && (hi = b)
    end
    span = hi > lo ? hi - lo : 1.0
    fills = Matrix{Paint}(undef, nx, ny)
    for j in 1:ny, i in 1:nx
        fills[i, j] = paint(_cmap(stops, (v[i, j] - lo) / span), alpha)
    end
    return _push!(ax, HeatmapPlot(xe, ye, fills))
end

# --- one-call forms and current-axis forms --------------------------------------------

for f in (:lines, :scatter, :stairs, :band, :barplot, :hist, :density, :ecdfplot, :rangebars, :poly, :heatmap)
    fb = Symbol(f, :!)
    @eval begin
        function $f(args...; figure=NamedTuple(), axis=NamedTuple(), kwargs...)
            @nospecialize
            fig = Figure(; figure...)
            ax = Axis(fig[1, 1]; axis...)
            $fb(ax, args...; kwargs...)
            return fig
        end
        function $fb(a1::AbstractArray, args...; kwargs...)
            @nospecialize
            return $fb(current_axis(), a1, args...; kwargs...)
        end
    end
    doc = """
        $f(args...; figure=(;), axis=(;), kwargs...) -> Figure

    Make a new figure with one axis and call [`$fb`](@ref) on it. `figure`
    and `axis` are keyword tuples passed to [`Figure`](@ref) and
    [`Axis`](@ref), e.g. `axis = (; xlabel = "x")`.
    """
    @eval @doc $doc $f
end
function hlines!(ys::Union{Real,AbstractVector}; kwargs...)
    @nospecialize
    return hlines!(current_axis(), ys; kwargs...)
end
function vlines!(xs::Union{Real,AbstractVector}; kwargs...)
    @nospecialize
    return vlines!(current_axis(), xs; kwargs...)
end
function text!(x::Union{Real,AbstractVector}, y; kwargs...)
    @nospecialize
    return text!(current_axis(), x, y; kwargs...)
end
