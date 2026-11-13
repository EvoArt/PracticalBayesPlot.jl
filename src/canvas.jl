# The drawing surface. The renderer (render.jl) lays out the figure in pixel
# coordinates (origin top left, y down) and draws through the functions in
# this file, which write SVG, TikZ (`tikz = true`) or CeTZ for Typst
# (`cetz = true`, cetz.jl). A TikZ picture uses `x = 0.75pt, y = -0.75pt`, so
# it takes the same coordinates and comes out the size of the SVG at 96 px
# per inch; CeTZ gets (x, -y) on a canvas of length 0.75pt.
#
# One concrete type with a flag, rather than a type per backend, keeps the
# renderer compiled once.

mutable struct Canvas
    io::IO
    tikz::Bool
    cetz::Bool
    body::IOBuffer                 # TikZ, CeTZ: the picture, written after the preamble
    d::IOBuffer                    # path data being built
    pathstate::Int                 # 0: no current point, 1: just moved, 2: drawing
    cx::Float64                    # current point
    cy::Float64
    colors::Dict{NTuple{3,Int},String}
    fs::Float64                    # figure font size, px
    gfill::Paint                   # TikZ: style of the open group
    gstroke::Paint
    glw::Float64
    tanchor::Symbol                # halign of the open text group
    sub::Vector{Vector{NTuple{2,Float64}}}   # CeTZ: subpaths being built
    subclosed::Vector{Bool}
    clips::Vector{NTuple{4,Float64}}         # CeTZ: clip rectangles (x0, y0, x1, y1), innermost last
end

function Canvas(io::IO, mode::Symbol, fs::Float64)
    mode in (:svg, :tikz, :cetz) || throw(ArgumentError("unknown output $mode"))
    return Canvas(io, mode === :tikz, mode === :cetz, IOBuffer(), IOBuffer(), 0, 0.0, 0.0,
                  Dict{NTuple{3,Int},String}(), fs, NOPAINT, NOPAINT, 0.0, :center,
                  Vector{NTuple{2,Float64}}[], Bool[], NTuple{4,Float64}[])
end

_out(c::Canvas) = c.tikz || c.cetz ? c.body : c.io

# --- numbers and text -----------------------------------------------------------------

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

# --- SVG style attributes ------------------------------------------------------------------

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

# --- figure -----------------------------------------------------------------------------------

const FONT = "Helvetica, Arial, sans-serif"

function _begin!(c::Canvas, W::Int, H::Int)
    c.cetz && return _cz_begin!(c, W, H)
    if c.tikz
        b = c.body
        print(b, "\\useasboundingbox (0,0) rectangle (", W, ',', H, ");\n")
    else
        print(c.io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"", W, "\" height=\"", H,
              "\" viewBox=\"0 0 ", W, ' ', H, "\" font-family=\"", FONT, "\" font-size=\"", _short(c.fs), "\">\n")
    end
end

function _finish!(c::Canvas)
    c.cetz && return _cz_finish!(c)
    if c.tikz
        io = c.io
        print(io, "\\begin{tikzpicture}[x=0.75pt,y=-0.75pt,every node/.style={inner sep=0pt,outer sep=0pt},font=")
        _fontcmd(io, c.fs, false)
        print(io, "]\n")
        for (rgb, name) in sort!(collect(c.colors); by=x -> length(last(x)) => last(x))
            print(io, "\\definecolor{", name, "}{RGB}{", rgb[1], ',', rgb[2], ',', rgb[3], "}\n")
        end
        write(io, take!(c.body))
        print(io, "\\end{tikzpicture}\n")
    else
        print(c.io, "</svg>\n")
    end
    return nothing
end

function _background!(c::Canvas, p::Paint, W::Int, H::Int)
    isvisible(p) || return
    c.cetz && return _cz_rect!(c, 0.0, 0.0, Float64(W), Float64(H), p, NOPAINT, 0.0)
    if c.tikz
        print(c.body, "\\path[")
        _tzfill(c, p)
        print(c.body, "] (0,0) rectangle (", W, ',', H, ");\n")
    else
        print(c.io, "<rect width=\"100%\" height=\"100%\"")
        _fill(c.io, p)
        print(c.io, "/>\n")
    end
end

# --- TikZ styles --------------------------------------------------------------------------

function _tzcolor(c::Canvas, p::Paint)
    rgb = _rgb255(p.css)
    rgb === nothing && return p.css     # an unknown name: hope xcolor knows it
    get!(() -> string("pbp", length(c.colors) + 1), c.colors, rgb)
end

function _tzfill(c::Canvas, p::Paint)
    b = c.body
    print(b, "fill=", _tzcolor(c, p))
    p.alpha < 1 && print(b, ",fill opacity=", _short(p.alpha))
end

function _tzdraw(c::Canvas, p::Paint, lw::Float64, dash::String)
    b = c.body
    print(b, "draw=", _tzcolor(c, p), ",line width=", _short(0.75lw), "pt")
    p.alpha < 1 && print(b, ",draw opacity=", _short(p.alpha))
    if !isempty(dash)
        print(b, ",dash pattern=")
        for (k, v) in enumerate(split(dash, ','))
            print(b, isodd(k) ? "on " : " off ", _short(0.75 * parse(Float64, v)), "pt")
        end
    end
end

# options for a filled and/or stroked shape; false if it draws nothing
function _tzstyle(c::Canvas, fill::Paint, stroke::Paint, lw::Float64, dash::String="", round::Bool=false)
    f = isvisible(fill)
    s = isvisible(stroke) && lw > 0
    (f || s) || return false
    print(c.body, "\\path[")
    f && _tzfill(c, fill)
    f && s && print(c.body, ',')
    s && _tzdraw(c, stroke, lw, dash)
    s && round && print(c.body, ",line join=round,line cap=round")
    print(c.body, ']')
    return true
end

# --- paths ------------------------------------------------------------------------------------

function _moveto!(c::Canvas, x::Float64, y::Float64)
    if c.cetz
        push!(c.sub, [(x, y)]); push!(c.subclosed, false)
        c.cx, c.cy = x, y
        return
    end
    d = c.d
    if c.tikz
        position(d) > 0 && print(d, ' ')
        print(d, '('); _num(d, x); print(d, ','); _num(d, y); print(d, ')')
    else
        print(d, 'M'); _num(d, x); print(d, ' '); _num(d, y)
    end
    c.pathstate = 1
    c.cx, c.cy = x, y
end

function _lineto!(c::Canvas, x::Float64, y::Float64)
    if c.cetz
        push!(c.sub[end], (x, y))
        c.cx, c.cy = x, y
        return
    end
    d = c.d
    if c.tikz
        print(d, " -- ("); _num(d, x); print(d, ','); _num(d, y); print(d, ')')
    else
        print(d, c.pathstate == 1 ? 'L' : ' ')
        _num(d, x); print(d, ' '); _num(d, y)
    end
    c.pathstate = 2
    c.cx, c.cy = x, y
end

function _hlineto!(c::Canvas, x::Float64)
    if c.tikz || c.cetz
        _lineto!(c, x, c.cy)
    else
        print(c.d, 'H'); _num(c.d, x)
        c.pathstate = 1
        c.cx = x
    end
end

function _vlineto!(c::Canvas, y::Float64)
    if c.tikz || c.cetz
        _lineto!(c, c.cx, y)
    else
        print(c.d, 'V'); _num(c.d, y)
        c.pathstate = 1
        c.cy = y
    end
end

function _closepath!(c::Canvas)
    c.cetz && (c.subclosed[end] = true; return)
    print(c.d, c.tikz ? " -- cycle" : "Z")
    c.pathstate = 0
end

# draw the path built since the last one
function _path!(c::Canvas, fill::Paint, stroke::Paint, lw::Float64, dash::String=""; round::Bool=false)
    c.cetz && return _cz_path!(c, fill, stroke, lw, dash, round)
    data = take!(c.d)
    c.pathstate = 0
    if c.tikz
        isempty(data) && return
        _tzstyle(c, fill, stroke, lw, dash, round) || return
        print(c.body, ' ')
        write(c.body, data)
        print(c.body, ";\n")
    else
        io = c.io
        print(io, "<path d=\"")
        write(io, data)
        print(io, "\"")
        _fill(io, fill)
        _stroke(io, stroke, lw, dash)
        round && isvisible(stroke) && lw > 0 && print(io, " stroke-linejoin=\"round\" stroke-linecap=\"round\"")
        print(io, "/>\n")
    end
end

# --- shapes; without a style they take the open group's ---------------------------------------

function _group!(c::Canvas, fill::Paint, stroke::Paint, lw::Float64; crisp::Bool=false)
    if c.tikz || c.cetz
        c.gfill, c.gstroke, c.glw = fill, stroke, lw
    else
        print(c.io, "<g")
        _fill(c.io, fill)
        _stroke(c.io, stroke, lw)
        crisp && print(c.io, " shape-rendering=\"crispEdges\"")
        print(c.io, ">\n")
    end
end

function _endgroup!(c::Canvas)
    if c.tikz || c.cetz
        c.gfill, c.gstroke, c.glw = NOPAINT, NOPAINT, 0.0
    else
        print(c.io, "</g>\n")
    end
end

function _rect!(c::Canvas, x::Float64, y::Float64, w::Float64, h::Float64)
    c.cetz && return _cz_rect!(c, x, y, w, h, c.gfill, c.gstroke, c.glw)
    if c.tikz
        _tzstyle(c, c.gfill, c.gstroke, c.glw) || return
        _tzrect(c, x, y, w, h)
    else
        print(c.io, "<rect")
        _attr(c.io, "x", x); _attr(c.io, "y", y); _attr(c.io, "width", w); _attr(c.io, "height", h)
        print(c.io, "/>\n")
    end
end

function _rect!(c::Canvas, x::Float64, y::Float64, w::Float64, h::Float64, fill::Paint, stroke::Paint, lw::Float64)
    c.cetz && return _cz_rect!(c, x, y, w, h, fill, stroke, lw)
    if c.tikz
        _tzstyle(c, fill, stroke, lw) || return
        _tzrect(c, x, y, w, h)
    else
        print(c.io, "<rect")
        _attr(c.io, "x", x); _attr(c.io, "y", y); _attr(c.io, "width", w); _attr(c.io, "height", h)
        _fill(c.io, fill)
        _stroke(c.io, stroke, lw)
        print(c.io, "/>\n")
    end
end

function _tzrect(c::Canvas, x::Float64, y::Float64, w::Float64, h::Float64)
    b = c.body
    print(b, " ("); _num(b, x); print(b, ','); _num(b, y); print(b, ") rectangle (")
    _num(b, x + w); print(b, ','); _num(b, y + h); print(b, ");\n")
end

function _circle!(c::Canvas, x::Float64, y::Float64, r::Float64)
    c.cetz && return _cz_circle!(c, x, y, r)
    if c.tikz
        _tzstyle(c, c.gfill, c.gstroke, c.glw) || return
        b = c.body
        print(b, " ("); _num(b, x); print(b, ','); _num(b, y); print(b, ") circle[radius=")
        _num(b, r); print(b, "];\n")
    else
        print(c.io, "<circle"); _attr(c.io, "cx", x); _attr(c.io, "cy", y); _attr(c.io, "r", r)
        print(c.io, "/>\n")
    end
end

# a closed polygon in the open group's style
function _polygon!(c::Canvas, x::NTuple{N,Float64}, y::NTuple{N,Float64}) where {N}
    c.cetz && return _cz_marker!(c, collect(zip(x, y)))
    if c.tikz
        _tzstyle(c, c.gfill, c.gstroke, c.glw) || return
        b = c.body
        for i in 1:N
            print(b, i == 1 ? " (" : " -- ("); _num(b, x[i]); print(b, ','); _num(b, y[i]); print(b, ')')
        end
        print(b, " -- cycle;\n")
    else
        io = c.io
        print(io, "<path d=\"M")
        for i in 1:N
            i == 2 && print(io, 'L')
            i > 2 && print(io, ' ')
            _num(io, x[i]); print(io, ' '); _num(io, y[i])
        end
        print(io, "Z\"/>\n")
    end
end

# --- clipping ---------------------------------------------------------------------------------

function _clip!(c::Canvas, x::Float64, y::Float64, w::Float64, h::Float64, id::String)
    c.cetz && return push!(c.clips, (x, y, x + w, y + h))
    if c.tikz
        print(c.body, "\\begin{scope}\n\\clip")
        _tzrect(c, x, y, w, h)
    else
        io = c.io
        print(io, "<clipPath id=\"", id, "\"><rect")
        _attr(io, "x", x); _attr(io, "y", y); _attr(io, "width", w); _attr(io, "height", h)
        print(io, "/></clipPath>\n<g clip-path=\"url(#", id, ")\">\n")
    end
end

_endclip!(c::Canvas) = c.cetz ? (pop!(c.clips); nothing) : print(_out(c), c.tikz ? "\\end{scope}\n" : "</g>\n")

# --- text -------------------------------------------------------------------------------------

# a group of texts sharing a horizontal alignment
function _textgroup!(c::Canvas, halign::Symbol)
    c.tanchor = halign
    c.tikz || c.cetz || print(c.io, "<g text-anchor=\"", _svganchor(halign), "\">\n")
end
function _endtextgroup!(c::Canvas)
    c.tanchor = :center
    c.tikz || c.cetz || print(c.io, "</g>\n")
end

_isblack(p::Paint) = p.alpha == 1 && (p.css == "#000" || _rgb255(p.css) == (0, 0, 0))

_svganchor(h::Symbol) = h === :left ? "start" : h === :right ? "end" : "middle"

"""
Text at `(x, y)`. `halign` is `:left`, `:center`, `:right`, or `:group` for
the open text group's; `valign` is `:baseline`, `:center` or `:top`. `size`
0 means the figure's font size. `latex`, if not empty, is what TikZ
typesets (in math mode) instead of `s`.
"""
function _text!(c::Canvas, x::Float64, y::Float64, s::AbstractString; halign::Symbol=:center,
                valign::Symbol=:baseline, size::Float64=0.0, bold::Bool=false, rotate::Bool=false,
                color::Paint=BLACK, latex::AbstractString="")
    if '\n' in s && !rotate
        # one text per line, the block aligned as a whole
        lines = split(s, '\n')
        lx = split(latex, '\n')
        length(lx) == length(lines) || (lx = fill("", length(lines)))
        n = length(lines)
        lh = 1.2 * (size > 0 ? size : c.fs)
        for i in 1:n
            yi = valign === :top ? y + (i - 1) * lh : valign === :center ? y + (i - (n + 1) / 2) * lh : y - (n - i) * lh
            _text!(c, x, yi, lines[i]; halign, valign, size, bold, color, latex=lx[i])
        end
        return
    end
    c.cetz && return _cz_text(c, x, y, s, halign === :group ? c.tanchor : halign, valign, size, bold, rotate, color)
    c.tikz && return _tztext(c, x, y, s, halign === :group ? c.tanchor : halign, valign, size, bold, rotate, color, latex)
    io = c.io
    print(io, "<text")
    _attr(io, "x", x)
    _attr(io, "y", y)
    halign === :group || print(io, " text-anchor=\"", _svganchor(halign), '"')
    valign === :top ? print(io, " dy=\".71em\"") : valign === :center ? print(io, " dy=\".32em\"") : nothing
    size > 0 && print(io, " font-size=\"", _short(size), '"')
    bold && print(io, " font-weight=\"bold\"")
    _isblack(color) || _fill(io, color)
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

function _fontcmd(io::IO, px::Float64, bold::Bool)
    pt = 0.75px
    print(io, "\\fontsize{", _short(pt), "}{", _short(1.2pt), "}\\selectfont")
    bold && print(io, "\\bfseries")
end

function _tztext(c::Canvas, x::Float64, y::Float64, s::AbstractString, h::Symbol, v::Symbol, size::Float64,
                 bold::Bool, rotate::Bool, color::Paint, latex::AbstractString)
    b = c.body
    vpart = v === :top ? "north" : v === :center ? "" : "base"
    hpart = h === :left ? "west" : h === :right ? "east" : ""
    anchor = isempty(vpart) ? (isempty(hpart) ? "center" : hpart) :
             isempty(hpart) ? vpart : string(vpart, ' ', hpart)
    print(b, "\\node[anchor=", anchor)
    if size > 0 || bold
        print(b, ",font=")
        size > 0 ? _fontcmd(b, size, bold) : print(b, "\\bfseries")
    end
    if !_isblack(color)
        print(b, ",text=", _tzcolor(c, color))
        color.alpha < 1 && print(b, ",text opacity=", _short(color.alpha))
    end
    rotate && print(b, ",rotate=90")
    print(b, "] at (")
    _num(b, x); print(b, ','); _num(b, y)
    print(b, ") {")
    if isempty(latex)
        _texesc(b, s)
    else
        print(b, '$', latex, '$')
    end
    print(b, "};\n")
end

# LaTeX for plain text: special characters escaped, common symbols as commands
const TEX_SYMBOLS = Dict{Char,String}(
    '−' => "\\ensuremath{-}", '×' => "\\ensuremath{\\times}", '·' => "\\ensuremath{\\cdot}",
    '±' => "\\ensuremath{\\pm}", '≤' => "\\ensuremath{\\leq}", '≥' => "\\ensuremath{\\geq}",
    '≈' => "\\ensuremath{\\approx}", '≠' => "\\ensuremath{\\neq}", '→' => "\\ensuremath{\\rightarrow}",
    '←' => "\\ensuremath{\\leftarrow}", '↔' => "\\ensuremath{\\leftrightarrow}", '∞' => "\\ensuremath{\\infty}",
    '∩' => "\\ensuremath{\\cap}", '∪' => "\\ensuremath{\\cup}", '∣' => "\\ensuremath{\\mid}",
    '⟂' => "\\ensuremath{\\perp}", '⊥' => "\\ensuremath{\\perp}", '∑' => "\\ensuremath{\\sum}",
    '∈' => "\\ensuremath{\\in}", '∅' => "\\ensuremath{\\emptyset}", '∝' => "\\ensuremath{\\propto}",
    '°' => "\\ensuremath{^\\circ}", '…' => "\\ldots{}", '–' => "--", '—' => "---",
    'ᶜ' => "\\ensuremath{^c}", '²' => "\\ensuremath{^2}", '³' => "\\ensuremath{^3}", '¹' => "\\ensuremath{^1}",
    '⁰' => "\\ensuremath{^0}", '₀' => "\\ensuremath{_0}", '₁' => "\\ensuremath{_1}", '₂' => "\\ensuremath{_2}",
    '₃' => "\\ensuremath{_3}", 'µ' => "\\ensuremath{\\mu}", 'Ω' => "\\ensuremath{\\Omega}",
    'α' => "\\ensuremath{\\alpha}", 'β' => "\\ensuremath{\\beta}", 'γ' => "\\ensuremath{\\gamma}",
    'δ' => "\\ensuremath{\\delta}", 'ε' => "\\ensuremath{\\varepsilon}", 'ϵ' => "\\ensuremath{\\epsilon}",
    'ζ' => "\\ensuremath{\\zeta}", 'η' => "\\ensuremath{\\eta}", 'θ' => "\\ensuremath{\\theta}",
    'ι' => "\\ensuremath{\\iota}", 'κ' => "\\ensuremath{\\kappa}", 'λ' => "\\ensuremath{\\lambda}",
    'μ' => "\\ensuremath{\\mu}", 'ν' => "\\ensuremath{\\nu}", 'ξ' => "\\ensuremath{\\xi}",
    'π' => "\\ensuremath{\\pi}", 'ρ' => "\\ensuremath{\\rho}", 'σ' => "\\ensuremath{\\sigma}",
    'τ' => "\\ensuremath{\\tau}", 'υ' => "\\ensuremath{\\upsilon}", 'φ' => "\\ensuremath{\\varphi}",
    'ϕ' => "\\ensuremath{\\phi}", 'χ' => "\\ensuremath{\\chi}", 'ψ' => "\\ensuremath{\\psi}",
    'ω' => "\\ensuremath{\\omega}", 'Γ' => "\\ensuremath{\\Gamma}", 'Δ' => "\\ensuremath{\\Delta}",
    'Θ' => "\\ensuremath{\\Theta}", 'Λ' => "\\ensuremath{\\Lambda}", 'Σ' => "\\ensuremath{\\Sigma}",
    'Φ' => "\\ensuremath{\\Phi}", 'Ψ' => "\\ensuremath{\\Psi}", 'Π' => "\\ensuremath{\\Pi}",
)

function _texesc(io::IO, s::AbstractString)
    for ch in s
        if ch == '\\'
            print(io, "\\textbackslash{}")
        elseif ch in ('#', '$', '%', '&', '_', '{', '}')
            print(io, '\\', ch)
        elseif ch == '~'
            print(io, "\\textasciitilde{}")
        elseif ch == '^'
            print(io, "\\textasciicircum{}")
        elseif ch == '<' || ch == '>' || ch == '|'
            print(io, "\\ensuremath{", ch == '|' ? "\\vert" : ch, '}')
        else
            print(io, get(TEX_SYMBOLS, ch, ch))
        end
    end
end
