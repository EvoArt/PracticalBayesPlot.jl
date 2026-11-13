# CeTZ output (Typst): the same drawing as svg(), written by the Canvas in
# CeTZ mode. CeTZ has y pointing up, so points are written as (x, -y), and it
# cannot clip, so clipping to the plot area happens here: lines and polygons
# are cut at the clip rectangle, markers and text outside it are dropped.

const CETZ_VERSION = "0.5.3"

"""
    cetz(fig; standalone=false, version="$CETZ_VERSION") -> String
    cetz(io, fig; standalone=false, version="$CETZ_VERSION")

The figure as Typst code drawing it with the [CeTZ](https://typst.app/universe/package/cetz)
package, for `#include` into a Typst document, so its text is set by Typst
in the document's font. `version` is the CeTZ version imported (0.5 needs
Typst 0.15 or later). The picture has the figure's size at 96 pixels per
inch (1 px = 0.75 pt), as the SVG does.

Text is written as Typst strings (never parsed as markup); the `latex` form
of text is not used. `standalone = true` adds a page sized to the figure, so
the file compiles on its own (`typst compile fig.typ`).
"""
cetz(fig::Figure; standalone::Bool=false, version::AbstractString=CETZ_VERSION) =
    sprint(io -> cetz(io, fig; standalone, version))

function cetz(io::IO, fig::Figure; standalone::Bool=false, version::AbstractString=CETZ_VERSION)
    standalone && print(io, "#set page(width: auto, height: auto, margin: 2pt)\n")
    print(io, "#import \"@preview/cetz:", version, "\"\n")
    _render(Canvas(io, :cetz, fig.fontsize), fig)
    return nothing
end

# --- canvas primitives -------------------------------------------------------------------

function _cz_begin!(c::Canvas, W::Int, H::Int)
    # an invisible rectangle fixes the canvas to the figure's size
    print(c.body, "rect((0, 0), (", W, ", ", -H, "), stroke: none, fill: none)\n")
end

function _cz_finish!(c::Canvas)
    print(c.io, "#cetz.canvas(length: 0.75pt, {\nimport cetz.draw: *\n")
    write(c.io, take!(c.body))
    print(c.io, "})\n")
    return nothing
end

_czpt(io::IO, x::Float64, y::Float64) = (print(io, '('); _num(io, x); print(io, ", "); _num(io, -y); print(io, ')'))

function _czcolor(io::IO, p::Paint)
    rgb = something(_rgb255(p.css), (0, 0, 0))
    print(io, "rgb(", rgb[1], ", ", rgb[2], ", ", rgb[3])
    p.alpha < 1 && print(io, ", ", round(Int, 255 * clamp(p.alpha, 0.0, 1.0)))
    print(io, ')')
end

function _czstyle(io::IO, fill::Paint, stroke::Paint, lw::Float64, dash::String, round::Bool)
    print(io, ", fill: ")
    isvisible(fill) ? _czcolor(io, fill) : print(io, "none")
    print(io, ", stroke: ")
    if isvisible(stroke) && lw > 0
        print(io, "(paint: ")
        _czcolor(io, stroke)
        print(io, ", thickness: ", _short(0.75lw), "pt")
        if !isempty(dash)
            print(io, ", dash: (array: (")
            for (k, v) in enumerate(split(dash, ','))
                k > 1 && print(io, ", ")
                print(io, _short(0.75 * parse(Float64, v)), "pt")
            end
            print(io, "))")
        end
        round && print(io, ", join: \"round\", cap: \"round\"")
        print(io, ')')
    else
        print(io, "none")
    end
end

_czdraws(fill::Paint, stroke::Paint, lw::Float64) = isvisible(fill) || (isvisible(stroke) && lw > 0)

function _czline(c::Canvas, pts::Vector{NTuple{2,Float64}}, closed::Bool, fill::Paint, stroke::Paint, lw::Float64,
                 dash::String, round::Bool)
    length(pts) >= 2 || return
    b = c.body
    print(b, "line(")
    for (k, (x, y)) in enumerate(pts)
        k > 1 && print(b, ", ")
        _czpt(b, x, y)
    end
    closed && print(b, ", close: true")
    _czstyle(b, closed ? fill : NOPAINT, stroke, lw, dash, round)
    print(b, ")\n")
end

function _cz_path!(c::Canvas, fill::Paint, stroke::Paint, lw::Float64, dash::String, round::Bool)
    sub, closed = c.sub, c.subclosed
    c.sub = Vector{NTuple{2,Float64}}[]
    c.subclosed = Bool[]
    _czdraws(fill, stroke, lw) || return
    for (pts, cl) in zip(sub, closed)
        if cl
            q = isempty(c.clips) ? pts : _clip_polygon(pts, c.clips[end])
            length(q) >= 3 && _czline(c, q, true, fill, stroke, lw, dash, round)
        else
            runs = isempty(c.clips) ? [pts] : _clip_polyline(pts, c.clips[end])
            for r in runs
                _czline(c, r, false, NOPAINT, stroke, lw, dash, round)
            end
        end
    end
end

function _cz_rect!(c::Canvas, x::Float64, y::Float64, w::Float64, h::Float64, fill::Paint, stroke::Paint, lw::Float64)
    _czdraws(fill, stroke, lw) || return
    x0, y0, x1, y1 = x, y, x + w, y + h
    if !isempty(c.clips)
        cx0, cy0, cx1, cy1 = c.clips[end]
        x0, y0, x1, y1 = max(x0, cx0), max(y0, cy0), min(x1, cx1), min(y1, cy1)
        (x1 > x0 && y1 > y0) || return
    end
    b = c.body
    print(b, "rect(")
    _czpt(b, x0, y0); print(b, ", "); _czpt(b, x1, y1)
    _czstyle(b, fill, stroke, lw, "", false)
    print(b, ")\n")
end

_czinside(c::Canvas, x::Float64, y::Float64) =
    isempty(c.clips) || (r = c.clips[end]; r[1] <= x <= r[3] && r[2] <= y <= r[4])

function _cz_circle!(c::Canvas, x::Float64, y::Float64, r::Float64)
    (_czdraws(c.gfill, c.gstroke, c.glw) && _czinside(c, x, y)) || return
    b = c.body
    print(b, "circle(")
    _czpt(b, x, y)
    print(b, ", radius: ")
    _num(b, r)
    _czstyle(b, c.gfill, c.gstroke, c.glw, "", false)
    print(b, ")\n")
end

function _cz_marker!(c::Canvas, pts::Vector{NTuple{2,Float64}})
    n = length(pts)
    cx, cy = sum(first, pts) / n, sum(last, pts) / n
    (_czdraws(c.gfill, c.gstroke, c.glw) && _czinside(c, cx, cy)) || return
    _czline(c, pts, true, c.gfill, c.gstroke, c.glw, "", false)
end

function _cz_text(c::Canvas, x::Float64, y::Float64, s::AbstractString, h::Symbol, v::Symbol, size::Float64,
                  bold::Bool, rotate::Bool, color::Paint)
    _czinside(c, x, y) || return
    b = c.body
    vpart = v === :top ? "north" : v === :center ? "" : "base"
    hpart = h === :left ? "west" : h === :right ? "east" : ""
    anchor = isempty(vpart) ? (isempty(hpart) ? "center" : hpart) :
             isempty(hpart) ? vpart : string(vpart, '-', hpart)
    print(b, "content(")
    _czpt(b, x, y)
    print(b, ", anchor: \"", anchor, "\"")
    rotate && print(b, ", angle: 90deg")
    print(b, ", text(size: ", _short(0.75 * (size > 0 ? size : c.fs)), "pt")
    bold && print(b, ", weight: \"bold\"")
    _isblack(color) || (print(b, ", fill: "); _czcolor(b, color))
    print(b, ", \"")
    for ch in s
        ch == '"' ? print(b, "\\\"") : ch == '\\' ? print(b, "\\\\") : print(b, ch)
    end
    print(b, "\"))\n")
end

# --- clipping to a rectangle (x0, y0, x1, y1) ----------------------------------------------

# Sutherland–Hodgman: the part of a polygon inside the rectangle
function _clip_polygon(P::Vector{NTuple{2,Float64}}, r::NTuple{4,Float64})
    for (f, k, lim) in ((>=, 1, r[1]), (<=, 1, r[3]), (>=, 2, r[2]), (<=, 2, r[4]))
        isempty(P) && break
        Q = NTuple{2,Float64}[]
        prev = P[end]
        for cur in P
            inc, inp = f(cur[k], lim), f(prev[k], lim)
            if inc != inp
                t = (lim - prev[k]) / (cur[k] - prev[k])
                push!(Q, (prev[1] + t * (cur[1] - prev[1]), prev[2] + t * (cur[2] - prev[2])))
            end
            inc && push!(Q, cur)
            prev = cur
        end
        P = Q
    end
    return P
end

# Liang–Barsky per segment: the parts of a polyline inside the rectangle, as runs
function _clip_polyline(P::Vector{NTuple{2,Float64}}, r::NTuple{4,Float64})
    runs = Vector{NTuple{2,Float64}}[]
    for i in 1:length(P)-1
        (ax, ay), (bx, by) = P[i], P[i+1]
        dx, dy = bx - ax, by - ay
        t0, t1 = 0.0, 1.0
        ok = true
        for (p, q) in ((-dx, ax - r[1]), (dx, r[3] - ax), (-dy, ay - r[2]), (dy, r[4] - ay))
            if p == 0
                q < 0 && (ok = false; break)
            else
                t = q / p
                p < 0 ? (t0 = max(t0, t)) : (t1 = min(t1, t))
            end
        end
        (ok && t0 <= t1) || continue
        a = (ax + t0 * dx, ay + t0 * dy)
        b = (ax + t1 * dx, ay + t1 * dy)
        if !isempty(runs) && t0 == 0 && last(runs[end]) == a
            push!(runs[end], b)
        else
            push!(runs, [a, b])
        end
    end
    return runs
end
