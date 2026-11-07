# SVG rendering: grid layout, limits and ticks per axis, then the plots.

const FONT = "Helvetica, Arial, sans-serif"
const TICK = 4.0       # tick length, px
const TGAP = 3.0       # tick to tick label
const LGAP = 5.0       # tick labels to axis label
const OUTER = 8.0      # figure padding
const CELLGAP = 12.0   # gap between grid cells

const _IDCOUNTER = Ref(0)

# --- low-level writers ------------------------------------------------------------

# coordinates with one decimal: enough for screen and print, keeps files small
function _num(io::IO, x::Float64)
    v = round(Int, clamp(x, -1e6, 1e6) * 10)
    if v < 0
        print(io, '-')
        v = -v
    end
    q, r = divrem(v, 10)
    print(io, q)
    r == 0 || (print(io, '.'); print(io, r))
    return nothing
end
_num(io::IO, x::Real) = _num(io, Float64(x))

_short(x::Real) = (s = string(round(Float64(x); digits=3)); endswith(s, ".0") ? s[1:end-2] : s)

function _esc(io::IO, s::AbstractString)
    for c in s
        c == '&' ? print(io, "&amp;") : c == '<' ? print(io, "&lt;") :
        c == '>' ? print(io, "&gt;") : c == '"' ? print(io, "&quot;") : print(io, c)
    end
end

function _attr(io::IO, name::String, x::Real)
    print(io, ' ', name, "=\"")
    _num(io, x)
    print(io, '"')
end

function _fill(io::IO, p::Paint)
    if !isvisible(p)
        print(io, " fill=\"none\"")
        return
    end
    print(io, " fill=\"", p.css, '"')
    p.alpha < 1 && print(io, " fill-opacity=\"", _short(p.alpha), '"')
end

function _stroke(io::IO, p::Paint, lw::Float64, dash::String="")
    if !isvisible(p) || lw <= 0
        print(io, " stroke=\"none\"")
        return
    end
    print(io, " stroke=\"", p.css, "\" stroke-width=\"", _short(lw), '"')
    p.alpha < 1 && print(io, " stroke-opacity=\"", _short(p.alpha), '"')
    isempty(dash) || print(io, " stroke-dasharray=\"", dash, '"')
end

# approximate text width for a Helvetica-like font, in px
function _textw(s::AbstractString, fs::Float64)
    w = 0.0
    for c in s
        w += c in "il.,:;'|!" ? 0.25 :
             c in " -()[]ftrjI/" ? 0.33 :
             c in "mwMW" ? 0.85 :
             isuppercase(c) ? 0.67 :
             isdigit(c) || c == MINUS ? 0.556 : 0.52
    end
    return w * fs
end

function _text(io::IO, x, y, s::AbstractString; anchor="middle", dy="", size=0.0,
               bold=false, rotate=false, color::Paint=Paint("#000", 1.0))
    print(io, "<text")
    _attr(io, "x", x)
    _attr(io, "y", y)
    isempty(anchor) || print(io, " text-anchor=\"", anchor, '"')
    isempty(dy) || print(io, " dy=\"", dy, '"')
    size > 0 && print(io, " font-size=\"", _short(size), '"')
    bold && print(io, " font-weight=\"bold\"")
    color.css == "#000" && color.alpha == 1 || _fill(io, color)
    if rotate
        print(io, " transform=\"rotate(-90 ")
        _num(io, x)
        print(io, ' ')
        _num(io, y)
        print(io, ")\"")
    end
    print(io, '>')
    _esc(io, s)
    print(io, "</text>\n")
end

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

_bounds!(b::Bounds, p::Union{LinesPlot,ScatterPlot,TextPlot}) = (_x!(b, p.x); _y!(b, p.y))
_bounds!(b::Bounds, p::BandPlot) = (_x!(b, p.x); _y!(b, p.lo); _y!(b, p.hi))
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
    ytw = isempty(yl) ? 0.0 : maximum(s -> _textw(s, fs), yl)
    left = TICK + TGAP + ytw + (isempty(ax.ylabel) ? 0.0 : LGAP + 1.2fs) + 2
    bottom = TICK + TGAP + 1.2fs + (isempty(ax.xlabel) ? 0.0 : LGAP + 1.2fs)
    top = isempty(ax.title) ? 0.7fs : 2.0fs
    right = max(0.7fs, isempty(xl) ? 0.0 : _textw(last(xl), fs) / 2)
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

function svg(io::IO, fig::Figure)
    W, H = fig.size
    fs = fig.fontsize
    id = (_IDCOUNTER[] += 1)
    print(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"", W, "\" height=\"", H,
          "\" viewBox=\"0 0 ", W, ' ', H, "\" font-family=\"", FONT, "\" font-size=\"", _short(fs), "\">\n")
    if isvisible(fig.backgroundcolor)
        print(io, "<rect width=\"100%\" height=\"100%\"")
        _fill(io, fig.backgroundcolor)
        print(io, "/>\n")
    end
    top0 = 0.0
    if !isempty(fig.title)
        _text(io, W / 2, OUTER, fig.title; dy=".9em", size=1.3fs, bold=true)
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
            _draw_axis(io, L, fs, "pbp$(id)c$(k)")
        end
    end
    print(io, "</svg>\n")
    return nothing
end

function _draw_axis(io::IO, L::AxLayout, fs::Float64, clipid::String)
    ax = L.ax
    x0 = L.rx0 + L.left
    y0 = L.ry0 + L.top
    w = L.rx1 - L.right - x0
    h = L.ry1 - L.bottom - y0
    (w > 2 && h > 2) || return
    t = Tr(x0, y0, w, h, L.lims...)

    # grid
    if (ax.xgridvisible && !isempty(L.xt)) || (ax.ygridvisible && !isempty(L.yt))
        print(io, "<path d=\"")
        if ax.xgridvisible
            for v in L.xt
                print(io, 'M'); _num(io, _tx(t, v)); print(io, ' '); _num(io, y0)
                print(io, 'V'); _num(io, y0 + h)
            end
        end
        if ax.ygridvisible
            for v in L.yt
                print(io, 'M'); _num(io, x0); print(io, ' '); _num(io, _ty(t, v))
                print(io, 'H'); _num(io, x0 + w)
            end
        end
        print(io, "\" stroke=\"#000\" stroke-opacity=\"0.1\" fill=\"none\"/>\n")
    end

    # plots, clipped to the plot area
    print(io, "<clipPath id=\"", clipid, "\"><rect")
    _attr(io, "x", x0); _attr(io, "y", y0); _attr(io, "width", w); _attr(io, "height", h)
    print(io, "/></clipPath>\n<g clip-path=\"url(#", clipid, ")\">\n")
    for p in ax.plots
        _draw(io, p, t)
    end
    print(io, "</g>\n")

    # frame and ticks
    print(io, "<rect")
    _attr(io, "x", x0); _attr(io, "y", y0); _attr(io, "width", w); _attr(io, "height", h)
    print(io, " fill=\"none\" stroke=\"#000\"/>\n")
    if !isempty(L.xt) || !isempty(L.yt)
        print(io, "<path d=\"")
        for v in L.xt
            print(io, 'M'); _num(io, _tx(t, v)); print(io, ' '); _num(io, y0 + h)
            print(io, 'v'); _num(io, TICK)
        end
        for v in L.yt
            print(io, 'M'); _num(io, x0); print(io, ' '); _num(io, _ty(t, v))
            print(io, 'h'); _num(io, -TICK)
        end
        print(io, "\" stroke=\"#000\"/>\n")
    end

    # tick labels
    if !isempty(L.xt)
        print(io, "<g text-anchor=\"middle\">\n")
        for (v, s) in zip(L.xt, L.xl)
            _text(io, _tx(t, v), y0 + h + TICK + TGAP, s; anchor="", dy=".71em")
        end
        print(io, "</g>\n")
    end
    if !isempty(L.yt)
        print(io, "<g text-anchor=\"end\">\n")
        for (v, s) in zip(L.yt, L.yl)
            _text(io, x0 - TICK - TGAP, _ty(t, v), s; anchor="", dy=".32em")
        end
        print(io, "</g>\n")
    end

    # axis labels and title
    isempty(ax.xlabel) ||
        _text(io, x0 + w / 2, y0 + h + TICK + TGAP + 1.2fs + LGAP, ax.xlabel; dy=".71em")
    isempty(ax.ylabel) ||
        _text(io, L.rx0 + 2, y0 + h / 2, ax.ylabel; dy=".71em", rotate=true)
    isempty(ax.title) ||
        _text(io, x0 + w / 2, y0 - 0.55fs, ax.title; size=1.15fs, bold=true)

    _draw_legend(io, ax, t, fs)
    return nothing
end

# --- plot primitives ------------------------------------------------------------------------

function _polyline(io::IO, t::Tr, x::Vector{Float64}, y::Vector{Float64})
    state = 0   # 0: pen up, 1: just moved, 2: drawing
    for i in eachindex(x, y)
        if isfinite(x[i]) && isfinite(y[i])
            if state == 0
                print(io, 'M')
                state = 1
            elseif state == 1
                print(io, 'L')
                state = 2
            else
                print(io, ' ')
            end
            _num(io, _tx(t, x[i])); print(io, ' '); _num(io, _ty(t, y[i]))
        else
            state = 0
        end
    end
end

function _draw(io::IO, p::LinesPlot, t::Tr)
    isempty(p.x) && return
    print(io, "<path d=\"")
    _polyline(io, t, p.x, p.y)
    print(io, "\" fill=\"none\"")
    _stroke(io, p.color, p.linewidth, p.dash)
    print(io, " stroke-linejoin=\"round\" stroke-linecap=\"round\"/>\n")
end

function _marker(io::IO, m::Symbol, cx::Float64, cy::Float64, s::Float64)
    r = s / 2
    if m === :circle
        print(io, "<circle"); _attr(io, "cx", cx); _attr(io, "cy", cy); _attr(io, "r", r)
    elseif m === :rect
        print(io, "<rect"); _attr(io, "x", cx - r); _attr(io, "y", cy - r)
        _attr(io, "width", s); _attr(io, "height", s)
    else
        print(io, "<path d=\"M")
        if m === :diamond
            q = 1.25r
            _num(io, cx); print(io, ' '); _num(io, cy - q); print(io, 'L')
            _num(io, cx + q); print(io, ' '); _num(io, cy); print(io, ' ')
            _num(io, cx); print(io, ' '); _num(io, cy + q); print(io, ' ')
            _num(io, cx - q); print(io, ' '); _num(io, cy)
        else
            sg = m === :utriangle ? 1.0 : -1.0
            _num(io, cx); print(io, ' '); _num(io, cy - sg * 1.15r); print(io, 'L')
            _num(io, cx + 1.1r); print(io, ' '); _num(io, cy + sg * 0.75r); print(io, ' ')
            _num(io, cx - 1.1r); print(io, ' '); _num(io, cy + sg * 0.75r)
        end
        print(io, "Z\"")
    end
    print(io, "/>\n")
end

function _draw(io::IO, p::ScatterPlot, t::Tr)
    isempty(p.x) && return
    print(io, "<g")
    _fill(io, p.color)
    _stroke(io, p.strokecolor, p.strokewidth)
    print(io, ">\n")
    for i in eachindex(p.x, p.y)
        x, y = p.x[i], p.y[i]
        (isfinite(x) && isfinite(y)) || continue
        _marker(io, p.marker, _tx(t, x), _ty(t, y), p.markersize)
    end
    print(io, "</g>\n")
end

function _draw(io::IO, p::BandPlot, t::Tr)
    n = length(p.x)
    i = 1
    print(io, "<path d=\"")
    while i <= n
        # one polygon per run of finite points
        ok(k) = isfinite(p.x[k]) && isfinite(p.lo[k]) && isfinite(p.hi[k])
        while i <= n && !ok(i)
            i += 1
        end
        j = i
        while j <= n && ok(j)
            j += 1
        end
        if j - i >= 2
            for k in i:j-1
                print(io, k == i ? 'M' : 'L')
                _num(io, _tx(t, p.x[k])); print(io, ' '); _num(io, _ty(t, p.hi[k]))
            end
            for k in j-1:-1:i
                print(io, 'L')
                _num(io, _tx(t, p.x[k])); print(io, ' '); _num(io, _ty(t, p.lo[k]))
            end
            print(io, 'Z')
        end
        i = j
    end
    print(io, "\"")
    _fill(io, p.color)
    print(io, " stroke=\"none\"/>\n")
end

function _draw(io::IO, p::BarsPlot, t::Tr)
    isempty(p.x) && return
    print(io, "<g")
    _fill(io, p.color)
    _stroke(io, p.strokecolor, p.strokewidth)
    print(io, ">\n")
    ybase = _ty(t, p.fillto)
    for i in eachindex(p.x)
        (isfinite(p.x[i]) && isfinite(p.h[i])) || continue
        xa = _tx(t, p.x[i] - p.width[i] / 2)
        xb = _tx(t, p.x[i] + p.width[i] / 2)
        yh = _ty(t, p.h[i])
        print(io, "<rect")
        _attr(io, "x", min(xa, xb)); _attr(io, "y", clamp(min(yh, ybase), -1e5, 1e5))
        _attr(io, "width", abs(xb - xa)); _attr(io, "height", min(abs(ybase - yh), 2e5))
        print(io, "/>\n")
    end
    print(io, "</g>\n")
end

function _draw(io::IO, p::RangeBarsPlot, t::Tr)
    isempty(p.pos) && return
    print(io, "<path d=\"")
    hw = p.whiskerwidth / 2
    for i in eachindex(p.pos)
        (isfinite(p.pos[i]) && isfinite(p.lo[i]) && isfinite(p.hi[i])) || continue
        if p.horizontal
            y = _ty(t, p.pos[i]); a = _tx(t, p.lo[i]); b = _tx(t, p.hi[i])
            print(io, 'M'); _num(io, a); print(io, ' '); _num(io, y); print(io, 'H'); _num(io, b)
            if hw > 0
                for e in (a, b)
                    print(io, 'M'); _num(io, e); print(io, ' '); _num(io, y - hw); print(io, 'V'); _num(io, y + hw)
                end
            end
        else
            x = _tx(t, p.pos[i]); a = _ty(t, p.lo[i]); b = _ty(t, p.hi[i])
            print(io, 'M'); _num(io, x); print(io, ' '); _num(io, a); print(io, 'V'); _num(io, b)
            if hw > 0
                for e in (a, b)
                    print(io, 'M'); _num(io, x - hw); print(io, ' '); _num(io, e); print(io, 'H'); _num(io, x + hw)
                end
            end
        end
    end
    print(io, "\" fill=\"none\"")
    _stroke(io, p.color, p.linewidth)
    print(io, "/>\n")
end

function _draw(io::IO, p::RefLinesPlot, t::Tr)
    isempty(p.vals) && return
    print(io, "<path d=\"")
    for v in p.vals
        isfinite(v) || continue
        if p.horizontal
            print(io, 'M'); _num(io, t.x0); print(io, ' '); _num(io, _ty(t, v)); print(io, 'H'); _num(io, t.x0 + t.w)
        else
            print(io, 'M'); _num(io, _tx(t, v)); print(io, ' '); _num(io, t.y0); print(io, 'V'); _num(io, t.y0 + t.h)
        end
    end
    print(io, "\" fill=\"none\"")
    _stroke(io, p.color, p.linewidth, p.dash)
    print(io, "/>\n")
end

function _draw(io::IO, p::TextPlot, t::Tr)
    anchor = p.halign === :left ? "start" : p.halign === :right ? "end" : "middle"
    dy = p.valign === :bottom ? "" : p.valign === :top ? ".71em" : ".32em"
    for i in eachindex(p.x)
        (isfinite(p.x[i]) && isfinite(p.y[i])) || continue
        _text(io, _tx(t, p.x[i]), _ty(t, p.y[i]), p.text[i]; anchor, dy, size=p.fontsize, color=p.color)
    end
end

# --- legend ------------------------------------------------------------------------------------

function _glyph(io::IO, p::Union{LinesPlot,RefLinesPlot}, gx, cy, gw, fs)
    print(io, "<path d=\"M"); _num(io, gx); print(io, ' '); _num(io, cy); print(io, 'H'); _num(io, gx + gw)
    print(io, "\" fill=\"none\"")
    _stroke(io, Paint(p.color.css, max(p.color.alpha, 0.6)), max(p.linewidth, 1.5), p.dash)
    print(io, "/>\n")
end
function _glyph(io::IO, p::ScatterPlot, gx, cy, gw, fs)
    print(io, "<g")
    _fill(io, p.color)
    _stroke(io, p.strokecolor, p.strokewidth)
    print(io, '>')
    _marker(io, p.marker, gx + gw / 2, cy, min(p.markersize, fs))
    print(io, "</g>\n")
end
function _glyph(io::IO, p::Union{BarsPlot,BandPlot}, gx, cy, gw, fs)
    print(io, "<rect")
    _attr(io, "x", gx + 2); _attr(io, "y", cy - 0.35fs); _attr(io, "width", gw - 4); _attr(io, "height", 0.7fs)
    _fill(io, p.color)
    p isa BarsPlot ? _stroke(io, p.strokecolor, p.strokewidth) : print(io, " stroke=\"none\"")
    print(io, "/>\n")
end
function _glyph(io::IO, p::RangeBarsPlot, gx, cy, gw, fs)
    print(io, "<path d=\"M"); _num(io, gx + gw / 2); print(io, ' '); _num(io, cy - 0.5fs)
    print(io, 'V'); _num(io, cy + 0.5fs); print(io, "\" fill=\"none\"")
    _stroke(io, p.color, p.linewidth)
    print(io, "/>\n")
end

function _draw_legend(io::IO, ax::Axis, t::Tr, fs::Float64)
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
    print(io, "<g>\n<rect")
    _attr(io, "x", bx); _attr(io, "y", by); _attr(io, "width", bw); _attr(io, "height", bh)
    print(io, " fill=\"#fff\" fill-opacity=\"0.85\" stroke=\"#000\" stroke-opacity=\"0.2\"/>\n")
    row = 0
    cy(r) = by + pad / 2 + rowh * (r - 0.5)
    if !isempty(title)
        row += 1
        _text(io, bx + bw / 2, cy(row), title; dy=".32em", bold=true)
    end
    for p in entries
        row += 1
        _glyph(io, p, bx + pad, cy(row), gw, fs)
        _text(io, bx + pad + gw + 5, cy(row), _label(p); anchor="", dy=".32em")
    end
    print(io, "</g>\n")
end
