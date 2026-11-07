# Figure, grid positions and axes.

abstract type PlotObj end

"""
    Axis(fig[i, j]; title="", xlabel="", ylabel="", xticks=nothing, yticks=nothing,
         limits=nothing, xgridvisible=true, ygridvisible=true)

A 2-d axis placed in cell `(i, j)` of a [`Figure`](@ref); `i` and `j` may be
ranges to span cells. Attributes can be changed afterwards, e.g.
`ax.ylabel = "density"`.

- `xticks`, `yticks`: `nothing` (automatic), a vector of positions, or a
  tuple `(positions, labels)`.
- `limits`: `(xlow, xhigh, ylow, yhigh)` or `((xlow, xhigh), (ylow, yhigh))`;
  any entry may be `nothing` to keep it automatic. See also [`xlims!`](@ref).
"""
mutable struct Axis
    rows::UnitRange{Int}
    cols::UnitRange{Int}
    title::String
    xlabel::String
    ylabel::String
    xticks::Any
    yticks::Any
    limits::NTuple{4,Float64}          # NaN = automatic
    xgridvisible::Bool
    ygridvisible::Bool
    plots::Vector{PlotObj}
    legend::Union{Nothing,Tuple{String,Symbol}}
    xcategories::Vector{String}
    ycategories::Vector{String}
    cycle::Int
end

_lim(v) = v === nothing ? NaN : Float64(v)
_parse_limits(::Nothing) = (NaN, NaN, NaN, NaN)
_parse_limits(l::NTuple{4,Any}) = (_lim(l[1]), _lim(l[2]), _lim(l[3]), _lim(l[4]))
function _parse_limits(l::Tuple{Any,Any})
    x = l[1] === nothing ? (nothing, nothing) : l[1]
    y = l[2] === nothing ? (nothing, nothing) : l[2]
    return (_lim(x[1]), _lim(x[2]), _lim(y[1]), _lim(y[2]))
end
_parse_limits(l) = throw(ArgumentError("limits must be (xlow, xhigh, ylow, yhigh) or ((xlow, xhigh), (ylow, yhigh)); got $(repr(l))"))

function Base.setproperty!(ax::Axis, name::Symbol, v)
    if name === :limits
        return setfield!(ax, :limits, _parse_limits(v))
    elseif name in (:title, :xlabel, :ylabel)
        return setfield!(ax, name, string(v))
    end
    return setfield!(ax, name, convert(fieldtype(Axis, name), v))
end

"""
    Figure(; size=(600, 450), fontsize=12, title="", backgroundcolor=:white)

A figure of `size` pixels (width, height). Place axes in it with
`Axis(fig[row, col])`. Display it in VS Code, Jupyter or Pluto, open it in a
browser with [`preview`](@ref), or write it with [`save`](@ref).
"""
mutable struct Figure
    size::Tuple{Int,Int}
    fontsize::Float64
    title::String
    backgroundcolor::Paint
    axes::Vector{Axis}
    colsizes::Dict{Int,Float64}
    rowsizes::Dict{Int,Float64}
end

function Figure(; size=(600, 450), fontsize=12, title="", backgroundcolor=:white)
    @nospecialize
    return Figure((Int(size[1]), Int(size[2])), Float64(fontsize), string(title),
                  paint(backgroundcolor, 1.0), Axis[], Dict{Int,Float64}(), Dict{Int,Float64}())
end

struct GridPos
    fig::Figure
    rows::UnitRange{Int}
    cols::UnitRange{Int}
end

function _cells(i)
    r = i isa Integer ? (Int(i):Int(i)) : i isa AbstractUnitRange ? (Int(first(i)):Int(last(i))) :
        throw(ArgumentError("grid positions take integers or ranges, got $(repr(i))"))
    (isempty(r) || first(r) < 1) && throw(ArgumentError("grid position $(repr(i)) is not a valid row/column"))
    return r
end

Base.getindex(f::Figure, i, j) = GridPos(f, _cells(i), _cells(j))

const CURRENT = Ref{Union{Nothing,Axis}}(nothing)

function Axis(gp::GridPos; title="", xlabel="", ylabel="", xticks=nothing, yticks=nothing,
              limits=nothing, xgridvisible::Bool=true, ygridvisible::Bool=true)
    @nospecialize
    ax = Axis(gp.rows, gp.cols, string(title), string(xlabel), string(ylabel), xticks, yticks,
              _parse_limits(limits), xgridvisible, ygridvisible, PlotObj[], nothing,
              String[], String[], 0)
    push!(gp.fig.axes, ax)
    CURRENT[] = ax
    return ax
end

"""
    current_axis()

The most recently created [`Axis`](@ref). The plotting functions without an
axis argument (`lines!(x, y)`) draw into it.
"""
function current_axis()
    ax = CURRENT[]
    ax === nothing && throw(ArgumentError("no axis yet: create one with `Axis(fig[1, 1])` or a plot function such as `lines(x, y)`"))
    return ax
end

"""
    Relative(fraction)

A column width or row height as a fraction of the figure, for
[`colsize!`](@ref) and [`rowsize!`](@ref).
"""
struct Relative
    x::Float64
end

"""
    colsize!(fig, j, Relative(f))
    colsize!(fig, j, f)

Make column `j` take fraction `f` of the figure's width; the other columns
share the rest equally.
"""
colsize!(fig::Figure, j::Integer, w::Relative) = (fig.colsizes[Int(j)] = w.x; fig)
colsize!(fig::Figure, j::Integer, w::Real) = colsize!(fig, j, Relative(w))

"""
    rowsize!(fig, i, Relative(f))
    rowsize!(fig, i, f)

Make row `i` take fraction `f` of the figure's height; the other rows share
the rest equally.
"""
rowsize!(fig::Figure, i::Integer, h::Relative) = (fig.rowsizes[Int(i)] = h.x; fig)
rowsize!(fig::Figure, i::Integer, h::Real) = rowsize!(fig, i, Relative(h))

"""
    xlims!(ax, low, high)
    xlims!(low, high)

Fix the x limits of `ax`, or of [`current_axis`](@ref) when `ax` is left
out; `nothing` leaves a limit automatic.
"""
function xlims!(ax::Axis, lo, hi)
    l = ax.limits
    setfield!(ax, :limits, (_lim(lo), _lim(hi), l[3], l[4]))
    return ax
end

"""
    ylims!(ax, low, high)
    ylims!(low, high)

Fix the y limits of `ax`, or of [`current_axis`](@ref) when `ax` is left
out; `nothing` leaves a limit automatic.
"""
function ylims!(ax::Axis, lo, hi)
    l = ax.limits
    setfield!(ax, :limits, (l[1], l[2], _lim(lo), _lim(hi)))
    return ax
end

"""
    limits!(ax, xlow, xhigh, ylow, yhigh)
    limits!(xlow, xhigh, ylow, yhigh)

Fix all four limits of `ax`, or of [`current_axis`](@ref) when `ax` is left
out; `nothing` leaves a limit automatic. `ax.limits = ((xlow, xhigh), (ylow,
yhigh))` does the same.
"""
limits!(ax::Axis, x1, x2, y1, y2) = (setfield!(ax, :limits, _parse_limits((x1, x2, y1, y2))); ax)
xlims!(lo, hi) = xlims!(current_axis(), lo, hi)
ylims!(lo, hi) = ylims!(current_axis(), lo, hi)
limits!(x1, x2, y1, y2) = limits!(current_axis(), x1, x2, y1, y2)

const LEGEND_POSITIONS = (:lt, :ct, :rt, :lc, :cc, :rc, :lb, :cb, :rb)

"""
    axislegend(ax, title=""; position=:rt)

Draw a legend inside `ax` listing every plot given a `label`. `position` is
two letters, horizontal then vertical: `:lt` (left top), `:rt`, `:rb`, `:lb`,
`:ct`, `:cb`, `:lc`, `:rc` or `:cc`.
"""
function axislegend(ax::Axis, title::AbstractString=""; position::Symbol=:rt)
    @nospecialize
    position in LEGEND_POSITIONS ||
        throw(ArgumentError("legend position must be one of $(join(LEGEND_POSITIONS, ", ")); got :$position"))
    ax.legend = (String(title), position)
    return ax
end
axislegend(title::AbstractString=""; position::Symbol=:rt) = axislegend(current_axis(), title; position)
