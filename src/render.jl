# Rendering: grid layout, limits and ticks per axis, then the plots, drawn on
# a Canvas (canvas.jl), which writes SVG or TikZ.

const TICK = 4.0       # tick length, px
const TGAP = 3.0       # tick to tick label
const LGAP = 5.0       # tick labels to axis label
const OUTER = 8.0      # figure padding
const CELLGAP = 12.0   # gap between grid cells

const _IDCOUNTER = Ref(0)

# --- data to pixel transform -----------------------------------------------------------

struct Tr
    x0::Float64
    y0::Float64
    w::Float64
    h::Float64
    xlo::Float64
    xhi::Float64
    ylo::Float64
    yhi::Float64
end
@inline _tx(t::Tr, x::Float64) = t.x0 + (x - t.xlo) / (t.xhi - t.xlo) * t.w
@inline _ty(t::Tr, y::Float64) = t.y0 + t.h - (y - t.ylo) / (t.yhi - t.ylo) * t.h

# --- limits -----------------------------------------------------------------------------

mutable struct Bounds
    xlo::Float64
    xhi::Float64
    ylo::Float64
    yhi::Float64
    bars::Bool
end

function _ext!(lo::Float64, hi::Float64, v::Vector{Float64})
    for a in v
        isfinite(a) || continue
        lo = min(lo, a)
        hi = max(hi, a)
    end
    return lo, hi
end
function _x!(b::Bounds, v::Vector{Float64})
    b.xlo, b.xhi = _ext!(b.xlo, b.xhi, v)
end
function _y!(b::Bounds, v::Vector{Float64})
    b.ylo, b.yhi = _ext!(b.ylo, b.yhi, v)
end

_bounds!(b::Bounds, p::Union{LinesPlot,ScatterPlot,TextPlot,PolyPlot}) = (_x!(b, p.x); _y!(b, p.y))
_bounds!(b::Bounds, p::BandPlot) = (_x!(b, p.x); _y!(b, p.lo); _y!(b, p.hi))
_bounds!(b::Bounds, p::HeatmapPlot) = (_x!(b, p.xe); _y!(b, p.ye))
function _bounds!(b::Bounds, p::BarsPlot)
    _x!(b, p.x .- p.width ./ 2)
    _x!(b, p.x .+ p.width ./ 2)
    _y!(b, p.h)
    _y!(b, [p.fillto])
    b.bars = true
end
function _bounds!(b::Bounds, p::RangeBarsPlot)
    if p.horizontal
        _y!(b, p.pos); _x!(b, p.lo); _x!(b, p.hi)
    else
        _x!(b, p.pos); _y!(b, p.lo); _y!(b, p.hi)
    end
end
_bounds!(b::Bounds, p::RefLinesPlot) = p.horizontal ? _y!(b, p.vals) : _x!(b, p.vals)

function _autorange(lo::Float64, hi::Float64, ncat::Int, zerofloor::Bool)
    if ncat > 0
        return min(lo, 0.5), max(hi, ncat + 0.5)
    end
    lo > hi && return 0.0, 1.0
    if lo == hi
        d = lo == 0 ? 0.5 : 0.1 * abs(lo)
        return lo - d, hi + d
    end
    pad = 0.05 * (hi - lo)
    a, b = lo - pad, hi + pad
    if zerofloor
        lo >= 0 && lo - pad < 0 && (a = 0.0)
        hi <= 0 && hi + pad > 0 && (b = 0.0)
    end
    return a, b
end

function _limits(ax::Axis)
    b = Bounds(Inf, -Inf, Inf, -Inf, false)
    for p in ax.plots
        _bounds!(b, p)
    end
    xlo, xhi = _autorange(b.xlo, b.xhi, length(ax.xcategories), false)
    ylo, yhi = _autorange(b.ylo, b.yhi, length(ax.ycategories), b.bars)
    l = ax.limits
    isnan(l[1]) || (xlo = l[1])
    isnan(l[2]) || (xhi = l[2])
    isnan(l[3]) || (ylo = l[3])
    isnan(l[4]) || (yhi = l[4])
    xhi > xlo || (xhi = xlo + 1)
    yhi > ylo || (yhi = ylo + 1)
    return xlo, xhi, ylo, yhi
end

# --- layout ------------------------------------------------------------------------------

# start and size of n tracks over `total` px; `fixed` maps track => fraction
function _tracks(total::Float64, n::Int, fixed::Dict{Int,Float64})
    avail = max(total - CELLGAP * (n - 1), 1.0)
    sizes = fill(NaN, n)
    used = 0.0
    for (j, f) in fixed
        j <= n || continue
        sizes[j] = f * avail
        used += sizes[j]
    end
    nauto = count(isnan, sizes)
    nauto > 0 && (sizes[isnan.(sizes)] .= max(avail - used, 0.0) / nauto)
    starts = zeros(n)
    for j in 2:n
        starts[j] = starts[j-1] + sizes[j-1] + CELLGAP
    end
    return starts, sizes
end

mutable struct AxLayout
    ax::Axis
    rx0::Float64
    ry0::Float64
    rx1::Float64
    ry1::Float64
    lims::NTuple{4,Float64}
    xt::Vector{Float64}
    xl::Vector{String}
    yt::Vector{Float64}
    yl::Vector{String}
    left::Float64
    right::Float64
    top::Float64
    bottom::Float64
end

_showxlabel(ax::Axis) = ax.xlabelvisible && !isempty(ax.xlabel)
_showylabel(ax::Axis) = ax.ylabelvisible && !isempty(ax.ylabel)
_bare(ax::Axis) = !(ax.xticksvisible || ax.yticksvisible || ax.xticklabelsvisible ||
                    ax.yticklabelsvisible || _showxlabel(ax) || _showylabel(ax))

function _prepare(ax::Axis, cs, cw, rs, rh, fs::Float64)
    rx0 = cs[first(ax.cols)]
    rx1 = cs[last(ax.cols)] + cw[last(ax.cols)]
    ry0 = rs[first(ax.rows)]
    ry1 = rs[last(ax.rows)] + rh[last(ax.rows)]
    lims = _limits(ax)
    xtarget = clamp(round(Int, (rx1 - rx0) / 90), 2, 8)
    ytarget = clamp(round(Int, (ry1 - ry0) / 55), 2, 7)
    xt, xl = _ticks(ax.xticks, ax.xcategories, lims[1], lims[2], xtarget)
    yt, yl = _ticks(ax.yticks, ax.ycategories, lims[3], lims[4], ytarget)
    ytw = isempty(yl) || !ax.yticklabelsvisible ? 0.0 : maximum(s -> _textw(s, fs), yl)
    if _bare(ax)
        left = right = bottom = 2.0
        top = isempty(ax.title) ? 2.0 : 2.0fs
    else
        left = (ax.yticksvisible ? TICK : 0.0) + (ax.yticklabelsvisible ? TGAP + ytw : 0.0) +
               (_showylabel(ax) ? LGAP + 1.2fs : 0.0) + 2
        bottom = (ax.xticksvisible ? TICK : 0.0) + (ax.xticklabelsvisible ? TGAP + 1.2fs : 0.0) +
                 (_showxlabel(ax) ? LGAP + 1.2fs : 0.0)
        top = isempty(ax.title) ? 0.7fs : 2.0fs
        right = max(0.7fs, isempty(xl) || !ax.xticklabelsvisible ? 0.0 : _textw(last(xl), fs) / 2)
    end
    return AxLayout(ax, rx0, ry0, rx1, ry1, lims, xt, xl, yt, yl, left, right, top, bottom)
end

# axes sharing a first column get the same left margin, etc., so that the
# plot areas line up
function _align_margins!(lays::Vector{AxLayout})
    left = Dict{Int,Float64}(); right = Dict{Int,Float64}()
    top = Dict{Int,Float64}(); bottom = Dict{Int,Float64}()
    for L in lays
        c1, c2 = first(L.ax.cols), last(L.ax.cols)
        r1, r2 = first(L.ax.rows), last(L.ax.rows)
        left[c1] = max(L.left, get(left, c1, 0.0))
        right[c2] = max(L.right, get(right, c2, 0.0))
        top[r1] = max(L.top, get(top, r1, 0.0))
        bottom[r2] = max(L.bottom, get(bottom, r2, 0.0))
    end
    for L in lays
        L.left = left[first(L.ax.cols)]
        L.right = right[last(L.ax.cols)]
        L.top = top[first(L.ax.rows)]
        L.bottom = bottom[last(L.ax.rows)]
    end
    return lays
end

# --- figure ------------------------------------------------------------------------------

"""
    svg(fig) -> String
    svg(io, fig)

The figure as an SVG document.
"""
svg(fig::Figure) = sprint(svg, fig)
svg(io::IO, fig::Figure) = _render(Canvas(io, :svg, fig.fontsize), fig)

function _render(c::Canvas, fig::Figure)
    W, H = fig.size
    fs = fig.fontsize
    id = (_IDCOUNTER[] += 1)
    _begin!(c, W, H)
    _background!(c, fig.backgroundcolor, W, H)
    top0 = 0.0
    if !isempty(fig.title)
        _text!(c, W / 2, OUTER + 0.25fs, fig.title; valign=:top, size=1.3fs, bold=true)
        top0 = 1.9fs
    end
    if !isempty(fig.axes)
        nr = maximum(a -> last(a.rows), fig.axes)
        nc = maximum(a -> last(a.cols), fig.axes)
        cs, cw = _tracks(W - 2OUTER, nc, fig.colsizes)
        rs, rh = _tracks(H - top0 - 2OUTER, nr, fig.rowsizes)
        cs .+= OUTER
        rs .+= OUTER + top0
        lays = [_prepare(a, cs, cw, rs, rh, fs) for a in fig.axes]
        _align_margins!(lays)
        for (k, L) in enumerate(lays)
            _draw_axis(c, L, fs, "pbp$(id)c$(k)")
        end
    end
    _finish!(c)
    return nothing
end

const GRID = Paint("#000", 0.1)

function _draw_axis(c::Canvas, L::AxLayout, fs::Float64, clipid::String)
    ax = L.ax
    x0 = L.rx0 + L.left
    y0 = L.ry0 + L.top
    w = L.rx1 - L.right - x0
    h = L.ry1 - L.bottom - y0
    (w > 2 && h > 2) || return
    xlo, xhi, ylo, yhi = L.lims
    # fixed aspect: shrink the plot area and centre it
    r = ax.aspect == -1 ? (xhi - xlo) / (yhi - ylo) : ax.aspect
    if r > 0
        if w / h > r
            nw = h * r
            x0 += (w - nw) / 2
            w = nw
        else
            nh = w / r
            y0 += (h - nh) / 2
            h = nh
        end
    end
    t = Tr(x0, y0, w, h, xlo, xhi, ylo, yhi)

    # grid
    if (ax.xgridvisible && !isempty(L.xt)) || (ax.ygridvisible && !isempty(L.yt))
        if ax.xgridvisible
            for v in L.xt
                _moveto!(c, _tx(t, v), y0); _vlineto!(c, y0 + h)
            end
        end
        if ax.ygridvisible
            for v in L.yt
                _moveto!(c, x0, _ty(t, v)); _hlineto!(c, x0 + w)
            end
        end
        _path!(c, NOPAINT, GRID, 1.0)
    end

    # plots, clipped to the plot area
    _clip!(c, x0, y0, w, h, clipid)
    for p in ax.plots
        _draw(c, p, t)
    end
    _endclip!(c)

    # frame and ticks
    ax.spinesvisible && _rect!(c, x0, y0, w, h, NOPAINT, BLACK, 1.0)
    if (ax.xticksvisible && !isempty(L.xt)) || (ax.yticksvisible && !isempty(L.yt))
        if ax.xticksvisible
            for v in L.xt
                _moveto!(c, _tx(t, v), y0 + h); _vlineto!(c, y0 + h + TICK)
            end
        end
        if ax.yticksvisible
            for v in L.yt
                _moveto!(c, x0, _ty(t, v)); _hlineto!(c, x0 - TICK)
            end
        end
        _path!(c, NOPAINT, BLACK, 1.0)
    end

    # tick labels
    xoff = ax.xticksvisible ? TICK : 0.0
    yoff = ax.yticksvisible ? TICK : 0.0
    if ax.xticklabelsvisible && !isempty(L.xt)
        _textgroup!(c, :center)
        for (v, s) in zip(L.xt, L.xl)
            _text!(c, _tx(t, v), y0 + h + xoff + TGAP, s; halign=:group, valign=:top)
        end
        _endtextgroup!(c)
    end
    if ax.yticklabelsvisible && !isempty(L.yt)
        _textgroup!(c, :right)
        for (v, s) in zip(L.yt, L.yl)
            _text!(c, x0 - yoff - TGAP, _ty(t, v), s; halign=:group, valign=:center)
        end
        _endtextgroup!(c)
    end

    # axis labels and title
    xlab = y0 + h + xoff + (ax.xticklabelsvisible ? TGAP + 1.2fs : 0.0) + LGAP
    _showxlabel(ax) && _text!(c, x0 + w / 2, xlab, ax.xlabel; valign=:top)
    _showylabel(ax) && _text!(c, L.rx0 + 2, y0 + h / 2, ax.ylabel; valign=:top, rotate=true)
    isempty(ax.title) || _text!(c, x0 + w / 2, y0 - 0.55fs, ax.title; size=1.15fs, bold=true)

    _draw_legend(c, ax, t, fs)
    return nothing
end

# --- plot primitives ------------------------------------------------------------------------

# the finite points as polylines (NaN breaks them)
function _polyline(c::Canvas, t::Tr, x::Vector{Float64}, y::Vector{Float64})
    up = true
    for i in eachindex(x, y)
        if isfinite(x[i]) && isfinite(y[i])
            px, py = _tx(t, x[i]), _ty(t, y[i])
            up ? _moveto!(c, px, py) : _lineto!(c, px, py)
            up = false
        else
            up = true
        end
    end
end

function _draw(c::Canvas, p::LinesPlot, t::Tr)
    isempty(p.x) && return
    _polyline(c, t, p.x, p.y)
    _path!(c, NOPAINT, p.color, p.linewidth, p.dash; round=true)
end

function _marker(c::Canvas, m::Symbol, cx::Float64, cy::Float64, s::Float64)
    r = s / 2
    if m === :circle
        _circle!(c, cx, cy, r)
    elseif m === :rect
        _rect!(c, cx - r, cy - r, s, s)
    elseif m === :diamond
        q = 1.25r
        _polygon!(c, (cx, cx + q, cx, cx - q), (cy - q, cy, cy + q, cy))
    else
        sg = m === :utriangle ? 1.0 : -1.0
        _polygon!(c, (cx, cx + 1.1r, cx - 1.1r), (cy - sg * 1.15r, cy + sg * 0.75r, cy + sg * 0.75r))
    end
end

function _draw(c::Canvas, p::ScatterPlot, t::Tr)
    isempty(p.x) && return
    _group!(c, p.color, p.strokecolor, p.strokewidth)
    for i in eachindex(p.x, p.y)
        x, y = p.x[i], p.y[i]
        (isfinite(x) && isfinite(y)) || continue
        _marker(c, p.marker, _tx(t, x), _ty(t, y), p.markersize)
    end
    _endgroup!(c)
end

# runs of at least two consecutive indices where `ok`
function _runs(ok, n::Int)
    runs = UnitRange{Int}[]
    i = 1
    while i <= n
        while i <= n && !ok(i)
            i += 1
        end
        j = i
        while j <= n && ok(j)
            j += 1
        end
        j - i >= 2 && push!(runs, i:j-1)
        i = j
    end
    return runs
end

function _draw(c::Canvas, p::BandPlot, t::Tr)
    for r in _runs(k -> isfinite(p.x[k]) && isfinite(p.lo[k]) && isfinite(p.hi[k]), length(p.x))
        for k in r
            px, py = _tx(t, p.x[k]), _ty(t, p.hi[k])
            k == first(r) ? _moveto!(c, px, py) : _lineto!(c, px, py)
        end
        for k in reverse(r)
            _lineto!(c, _tx(t, p.x[k]), _ty(t, p.lo[k]))
        end
        _closepath!(c)
    end
    _path!(c, p.color, NOPAINT, 0.0)
end

function _draw(c::Canvas, p::PolyPlot, t::Tr)
    for r in _runs(k -> isfinite(p.x[k]) && isfinite(p.y[k]), length(p.x))
        for k in r
            px, py = _tx(t, p.x[k]), _ty(t, p.y[k])
            k == first(r) ? _moveto!(c, px, py) : _lineto!(c, px, py)
        end
        _closepath!(c)
    end
    _path!(c, p.color, p.strokecolor, p.strokewidth, p.dash; round=true)
end

function _draw(c::Canvas, p::BarsPlot, t::Tr)
    isempty(p.x) && return
    _group!(c, p.color, p.strokecolor, p.strokewidth)
    ybase = _ty(t, p.fillto)
    for i in eachindex(p.x)
        (isfinite(p.x[i]) && isfinite(p.h[i])) || continue
        xa = _tx(t, p.x[i] - p.width[i] / 2)
        xb = _tx(t, p.x[i] + p.width[i] / 2)
        yh = _ty(t, p.h[i])
        _rect!(c, min(xa, xb), clamp(min(yh, ybase), -1e5, 1e5), abs(xb - xa), min(abs(ybase - yh), 2e5))
    end
    _endgroup!(c)
end

# each cell is stroked in its own colour too, which hides the hairline seams
# viewers draw between abutting rectangles
function _draw(c::Canvas, p::HeatmapPlot, t::Tr)
    nx, ny = size(p.fills)
    for j in 1:ny, i in 1:nx
        f = p.fills[i, j]
        isvisible(f) || continue
        xa, xb = _tx(t, p.xe[i]), _tx(t, p.xe[i+1])
        ya, yb = _ty(t, p.ye[j+1]), _ty(t, p.ye[j])
        _rect!(c, min(xa, xb), min(ya, yb), abs(xb - xa), abs(yb - ya), f, f, 0.5)
    end
end

function _draw(c::Canvas, p::RangeBarsPlot, t::Tr)
    isempty(p.pos) && return
    hw = p.whiskerwidth / 2
    for i in eachindex(p.pos)
        (isfinite(p.pos[i]) && isfinite(p.lo[i]) && isfinite(p.hi[i])) || continue
        if p.horizontal
            y = _ty(t, p.pos[i]); a = _tx(t, p.lo[i]); b = _tx(t, p.hi[i])
            _moveto!(c, a, y); _hlineto!(c, b)
            if hw > 0
                for e in (a, b)
                    _moveto!(c, e, y - hw); _vlineto!(c, y + hw)
                end
            end
        else
            x = _tx(t, p.pos[i]); a = _ty(t, p.lo[i]); b = _ty(t, p.hi[i])
            _moveto!(c, x, a); _vlineto!(c, b)
            if hw > 0
                for e in (a, b)
                    _moveto!(c, x - hw, e); _hlineto!(c, x + hw)
                end
            end
        end
    end
    _path!(c, NOPAINT, p.color, p.linewidth)
end

function _draw(c::Canvas, p::RefLinesPlot, t::Tr)
    isempty(p.vals) && return
    for v in p.vals
        isfinite(v) || continue
        if p.horizontal
            _moveto!(c, t.x0, _ty(t, v)); _hlineto!(c, t.x0 + t.w)
        else
            _moveto!(c, _tx(t, v), t.y0); _vlineto!(c, t.y0 + t.h)
        end
    end
    _path!(c, NOPAINT, p.color, p.linewidth, p.dash)
end

function _draw(c::Canvas, p::TextPlot, t::Tr)
    va = p.valign === :bottom ? :baseline : p.valign
    size = p.dataspace ? p.fontsize * t.w / (t.xhi - t.xlo) : p.fontsize
    for i in eachindex(p.x)
        (isfinite(p.x[i]) && isfinite(p.y[i])) || continue
        _text!(c, _tx(t, p.x[i]), _ty(t, p.y[i]), p.text[i]; halign=p.halign, valign=va, size, color=p.color,
               latex=isempty(p.latex) ? "" : p.latex[i])
    end
end

# --- legend ------------------------------------------------------------------------------------

function _glyph(c::Canvas, p::Union{LinesPlot,RefLinesPlot}, gx, cy, gw, fs)
    _moveto!(c, gx, cy); _hlineto!(c, gx + gw)
    _path!(c, NOPAINT, Paint(p.color.css, max(p.color.alpha, 0.6)), max(p.linewidth, 1.5), p.dash)
end
function _glyph(c::Canvas, p::ScatterPlot, gx, cy, gw, fs)
    _group!(c, p.color, p.strokecolor, p.strokewidth)
    _marker(c, p.marker, gx + gw / 2, cy, min(p.markersize, fs))
    _endgroup!(c)
end
function _glyph(c::Canvas, p::Union{BarsPlot,BandPlot,PolyPlot}, gx, cy, gw, fs)
    stroke, lw = p isa BandPlot ? (NOPAINT, 0.0) : (p.strokecolor, p.strokewidth)
    _rect!(c, gx + 2, cy - 0.35fs, gw - 4, 0.7fs, p.color, stroke, lw)
end
function _glyph(c::Canvas, p::RangeBarsPlot, gx, cy, gw, fs)
    _moveto!(c, gx + gw / 2, cy - 0.5fs); _vlineto!(c, cy + 0.5fs)
    _path!(c, NOPAINT, p.color, p.linewidth)
end
_glyph(c::Canvas, p::Union{TextPlot,HeatmapPlot}, gx, cy, gw, fs) = nothing

const LEGENDFILL = Paint("#fff", 0.85)
const LEGENDSTROKE = Paint("#000", 0.2)

function _draw_legend(c::Canvas, ax::Axis, t::Tr, fs::Float64)
    ax.legend === nothing && return
    title, pos = ax.legend
    entries = PlotObj[]
    lw = 0.0
    for p in ax.plots
        isempty(_label(p)) && continue
        push!(entries, p)
        lw = max(lw, _textw(_label(p), fs))
    end
    isempty(entries) && isempty(title) && return
    rowh = 1.4fs
    gw = 22.0
    pad = 6.0
    tw = isempty(title) ? 0.0 : 1.08 * _textw(title, fs)
    bw = max(pad + gw + 5 + lw + pad, tw + 2pad)
    nrow = length(entries) + !isempty(title)
    bh = rowh * nrow + pad
    s = string(pos)
    inset = 8.0
    bx = s[1] == 'l' ? t.x0 + inset : s[1] == 'r' ? t.x0 + t.w - inset - bw : t.x0 + (t.w - bw) / 2
    by = s[2] == 't' ? t.y0 + inset : s[2] == 'b' ? t.y0 + t.h - inset - bh : t.y0 + (t.h - bh) / 2
    _rect!(c, bx, by, bw, bh, LEGENDFILL, LEGENDSTROKE, 1.0)
    row = 0
    cy(r) = by + pad / 2 + rowh * (r - 0.5)
    if !isempty(title)
        row += 1
        _text!(c, bx + bw / 2, cy(row), title; valign=:center, bold=true)
    end
    for p in entries
        row += 1
        _glyph(c, p, bx + pad, cy(row), gw, fs)
        _text!(c, bx + pad + gw + 5, cy(row), _label(p); halign=:left, valign=:center)
    end
end
