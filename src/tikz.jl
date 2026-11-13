# TikZ output: the same drawing as svg(), written by the Canvas in TikZ mode.

const STANDALONE_PREAMBLE = """
\\documentclass[tikz,border=2pt]{standalone}
\\usepackage[T1]{fontenc}
\\usepackage{lmodern}
\\usepackage{amsmath,amssymb}
"""

"""
    tikz(fig; standalone=false) -> String
    tikz(io, fig; standalone=false)

The figure as a `tikzpicture`, for `\\input` into a LaTeX document, so its
text is typeset by LaTeX in the document's font. It needs only the `tikz`
package (which loads `xcolor`); a scalable font such as `lmodern` gives
exact font sizes. The picture has the figure's size at 96 pixels per inch
(1 px = 0.75 pt), as the SVG does.

Text given a `latex` form ([`text!`](@ref)) is typeset in math mode;
other text is escaped, with common Unicode symbols (Greek letters, `∩`,
`≤`, `→`, ...) replaced by LaTeX commands so that it compiles with pdfLaTeX.

`standalone = true` wraps the picture in a complete document (class
`standalone`) that compiles on its own.
"""
tikz(fig::Figure; standalone::Bool=false) = sprint(io -> tikz(io, fig; standalone))

function tikz(io::IO, fig::Figure; standalone::Bool=false)
    standalone && print(io, STANDALONE_PREAMBLE, "\\begin{document}\n")
    _render(Canvas(io, true, fig.fontsize), fig)
    standalone && print(io, "\\end{document}\n")
    return nothing
end
