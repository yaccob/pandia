-- Pandoc Lua filter: renders diagram code blocks to images
-- Supported: plantuml, graphviz/dot, mermaid, ditaa, tikz
-- LaTeX math is handled natively by pandoc
--
-- For PDF output: vector graphics (PDF) where possible, PNG only for ditaa
-- For HTML output: SVG where possible, PNG for ditaa and tikz

local pipe = pandoc.pipe

local filecounter = 0
local imgdir = "img"
local is_html = false
local is_pdf = false

-- Optional puppeteer config for mermaid (needed in containers)
local mmdc_puppeteer = os.getenv("MMDC_PUPPETEER_CONFIG")
local mmdc_extra = mmdc_puppeteer and (" -p " .. mmdc_puppeteer) or ""

local function ensure_imgdir()
  os.execute("mkdir -p " .. imgdir)
end

-- Convert SVG to PDF using rsvg-convert (for LaTeX/PDF embedding)
local function svg_to_pdf(svgfile, pdffile)
  os.execute("rsvg-convert -f pdf -o " .. pdffile .. " " .. svgfile)
end

local function render_plantuml(code)
  ensure_imgdir()
  filecounter = filecounter + 1
  local basename = imgdir .. "/plantuml-" .. filecounter
  local infile = basename .. ".puml"
  local f = io.open(infile, "w")
  f:write(code)
  f:close()

  if is_html then
    local outfile = basename .. ".svg"
    pipe("plantuml", {"-tsvg", infile}, "")
    os.remove(infile)
    return outfile
  else
    -- Generate SVG, then convert to PDF for crisp vector output
    local svgfile = basename .. ".svg"
    local outfile = basename .. ".pdf"
    pipe("plantuml", {"-tsvg", infile}, "")
    svg_to_pdf(svgfile, outfile)
    os.remove(infile)
    return outfile
  end
end

local function render_graphviz(code, engine)
  ensure_imgdir()
  filecounter = filecounter + 1
  local basename = imgdir .. "/graphviz-" .. filecounter

  if is_html then
    local outfile = basename .. ".svg"
    local f = io.open(outfile, "w")
    f:write(pipe(engine or "dot", {"-Tsvg"}, code))
    f:close()
    return outfile
  else
    -- Graphviz can output PDF directly
    local outfile = basename .. ".pdf"
    local f = io.open(outfile, "w")
    f:write(pipe(engine or "dot", {"-Tpdf"}, code))
    f:close()
    return outfile
  end
end

local function render_mermaid(code)
  ensure_imgdir()
  filecounter = filecounter + 1
  local basename = imgdir .. "/mermaid-" .. filecounter
  local infile = basename .. ".mmd"
  local f = io.open(infile, "w")
  f:write(code)
  f:close()

  if is_html then
    local outfile = basename .. ".svg"
    os.execute("mmdc -i " .. infile .. " -o " .. outfile .. mmdc_extra .. " --quiet 2>/dev/null")
    os.remove(infile)
    return outfile
  else
    -- mmdc can output PDF directly (avoids foreignObject issues with rsvg-convert)
    local outfile = basename .. ".pdf"
    os.execute("mmdc -i " .. infile .. " -o " .. outfile .. mmdc_extra .. " --quiet 2>/dev/null")
    os.remove(infile)
    return outfile
  end
end

local function render_ditaa(code)
  -- ditaa is raster-only (ASCII art → pixels)
  ensure_imgdir()
  filecounter = filecounter + 1
  local basename = imgdir .. "/ditaa-" .. filecounter
  local wrapped = "@startditaa\n" .. code .. "\n@endditaa"
  local outfile = basename .. ".png"
  local infile = basename .. ".puml"
  local f = io.open(infile, "w")
  f:write(wrapped)
  f:close()
  pipe("plantuml", {"-tpng", infile}, "")
  os.remove(infile)
  return outfile
end

local function render_tikz(code)
  ensure_imgdir()
  filecounter = filecounter + 1
  local basename = imgdir .. "/tikz-" .. filecounter
  local texfile = basename .. ".tex"
  local pdffile = basename .. ".pdf"

  -- Wrap in standalone LaTeX document
  local doc = "\\documentclass[tikz,border=2pt]{standalone}\n"
  -- Allow additional packages via \usepackage in the code block
  if not code:match("\\begin{tikzpicture}") then
    doc = doc .. "\\begin{document}\n\\begin{tikzpicture}\n"
      .. code
      .. "\n\\end{tikzpicture}\n\\end{document}\n"
  else
    doc = doc .. "\\begin{document}\n" .. code .. "\n\\end{document}\n"
  end

  local f = io.open(texfile, "w")
  f:write(doc)
  f:close()

  -- Compile to PDF (run twice for references, suppress output)
  os.execute("pdflatex -interaction=nonstopmode -output-directory=" .. imgdir
    .. " " .. texfile .. " >/dev/null 2>&1")

  -- Clean up aux files
  os.remove(basename .. ".aux")
  os.remove(basename .. ".log")
  os.remove(texfile)

  if is_html then
    -- Convert PDF to high-resolution PNG for HTML (no pdf2svg/dvisvgm available)
    local pngfile = basename .. ".png"
    os.execute("gs -sDEVICE=pngalpha -r300 -dNOPAUSE -dBATCH -dQUIET"
      .. " -sOutputFile=" .. pngfile .. " " .. pdffile .. " 2>/dev/null")
    return pngfile
  else
    return pdffile
  end
end

function CodeBlock(block)
  -- Detect output format once per block (FORMAT can change)
  is_html = FORMAT:match("html") ~= nil
  is_pdf = not is_html

  local lang = block.classes[1]
  local caption = block.attributes.caption or ""
  local outfile = nil

  if lang == "plantuml" then
    outfile = render_plantuml(block.text)
  elseif lang == "graphviz" or lang == "dot" then
    local engine = block.attributes.engine or "dot"
    outfile = render_graphviz(block.text, engine)
  elseif lang == "mermaid" then
    outfile = render_mermaid(block.text)
  elseif lang == "ditaa" then
    outfile = render_ditaa(block.text)
  elseif lang == "tikz" then
    outfile = render_tikz(block.text)
  end

  if outfile then
    return pandoc.Para{pandoc.Image({pandoc.Str(caption)}, outfile)}
  end
end
