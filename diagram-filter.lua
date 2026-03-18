-- Pandoc Lua filter: renders diagram code blocks to images
-- Supported: plantuml, graphviz/dot, mermaid, ditaa, tikz
-- LaTeX math is handled natively by pandoc
--
-- For PDF output: vector graphics (PDF) where possible, PNG only for ditaa
-- For HTML output: SVG where possible, PNG for ditaa and tikz
--
-- Set PANDIA_PARALLEL=1 to render diagrams in parallel (two-pass filter)

local filecounter = 0
local imgdir = "img"
local is_html = false
local is_pdf = false
local parallel = os.getenv("PANDIA_PARALLEL") == "1"

-- Optional puppeteer config for mermaid (needed in containers)
local mmdc_puppeteer = os.getenv("MMDC_PUPPETEER_CONFIG")
local mmdc_extra = mmdc_puppeteer and (" -p " .. mmdc_puppeteer) or ""

local function ensure_imgdir()
  os.execute("mkdir -p " .. imgdir)
end

local function detect_format()
  is_html = FORMAT:match("html") ~= nil
  is_pdf = not is_html
end

------------------------------------------------------------------------
-- Prepare functions: write input files, return (outfile, cmd, cleanup)
------------------------------------------------------------------------

local function prepare_plantuml(code)
  ensure_imgdir()
  filecounter = filecounter + 1
  local basename = imgdir .. "/plantuml-" .. filecounter
  local infile = basename .. ".puml"
  local f = io.open(infile, "w")
  f:write(code)
  f:close()

  if is_html then
    local outfile = basename .. ".svg"
    return outfile, "plantuml -tsvg " .. infile, {infile}
  else
    local svgfile = basename .. ".svg"
    local outfile = basename .. ".pdf"
    return outfile,
      "plantuml -tsvg " .. infile
        .. " && rsvg-convert -f pdf -o " .. outfile .. " " .. svgfile,
      {infile, svgfile}
  end
end

local function prepare_graphviz(code, engine)
  ensure_imgdir()
  filecounter = filecounter + 1
  local basename = imgdir .. "/graphviz-" .. filecounter
  local infile = basename .. ".dot"
  local f = io.open(infile, "w")
  f:write(code)
  f:close()
  engine = engine or "dot"

  if is_html then
    local outfile = basename .. ".svg"
    return outfile, engine .. " -Tsvg -o " .. outfile .. " " .. infile, {infile}
  else
    local outfile = basename .. ".pdf"
    return outfile, engine .. " -Tpdf -o " .. outfile .. " " .. infile, {infile}
  end
end

local function prepare_mermaid(code)
  ensure_imgdir()
  filecounter = filecounter + 1
  local basename = imgdir .. "/mermaid-" .. filecounter
  local infile = basename .. ".mmd"
  local f = io.open(infile, "w")
  f:write(code)
  f:close()

  if is_html then
    local outfile = basename .. ".svg"
    return outfile,
      "mmdc -i " .. infile .. " -o " .. outfile .. mmdc_extra .. " --quiet 2>/dev/null",
      {infile}
  else
    local outfile = basename .. ".pdf"
    return outfile,
      "mmdc -i " .. infile .. " -o " .. outfile .. mmdc_extra .. " --quiet 2>/dev/null",
      {infile}
  end
end

local function prepare_ditaa(code)
  ensure_imgdir()
  filecounter = filecounter + 1
  local basename = imgdir .. "/ditaa-" .. filecounter
  local wrapped = "@startditaa\n" .. code .. "\n@endditaa"
  local outfile = basename .. ".png"
  local infile = basename .. ".puml"
  local f = io.open(infile, "w")
  f:write(wrapped)
  f:close()
  return outfile, "plantuml -tpng " .. infile, {infile}
end

local function prepare_tikz(code)
  ensure_imgdir()
  filecounter = filecounter + 1
  local basename = imgdir .. "/tikz-" .. filecounter
  local texfile = basename .. ".tex"
  local pdffile = basename .. ".pdf"

  local doc = "\\documentclass[tikz,border=2pt]{standalone}\n"
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

  local compile = "pdflatex -interaction=nonstopmode -output-directory=" .. imgdir
    .. " " .. texfile .. " >/dev/null 2>&1"
  local cleanup = {texfile, basename .. ".aux", basename .. ".log"}

  if is_html then
    local pngfile = basename .. ".png"
    local cmd = compile
      .. " && gs -sDEVICE=pngalpha -r300 -dNOPAUSE -dBATCH -dQUIET"
      .. " -sOutputFile=" .. pngfile .. " " .. pdffile .. " 2>/dev/null"
    return pngfile, cmd, cleanup
  else
    return pdffile, compile, cleanup
  end
end

local function get_prepare_fn(lang, attrs)
  if lang == "plantuml" then
    return prepare_plantuml
  elseif lang == "graphviz" or lang == "dot" then
    return function(code) return prepare_graphviz(code, attrs.engine) end
  elseif lang == "mermaid" then
    return prepare_mermaid
  elseif lang == "ditaa" then
    return prepare_ditaa
  elseif lang == "tikz" then
    return prepare_tikz
  end
  return nil
end

------------------------------------------------------------------------
-- Sequential mode (default): single-pass filter
------------------------------------------------------------------------

local function seq_CodeBlock(block)
  detect_format()
  local lang = block.classes[1]
  local caption = block.attributes.caption or ""
  local prepare = get_prepare_fn(lang, block.attributes)
  if not prepare then return nil end

  local outfile, cmd, cleanup = prepare(block.text)
  os.execute(cmd)
  if cleanup then
    for _, f in ipairs(cleanup) do os.remove(f) end
  end
  return pandoc.Para{pandoc.Image({pandoc.Str(caption)}, outfile)}
end

------------------------------------------------------------------------
-- Parallel mode: two-pass filter
------------------------------------------------------------------------

local pending = {}

local function par_pass1_CodeBlock(block)
  detect_format()
  local lang = block.classes[1]
  local caption = block.attributes.caption or ""
  local prepare = get_prepare_fn(lang, block.attributes)
  if not prepare then return nil end

  local outfile, cmd, cleanup = prepare(block.text)
  local id = "pandia-job-" .. (#pending + 1)
  table.insert(pending, {
    id = id, outfile = outfile, caption = caption, cmd = cmd, cleanup = cleanup
  })
  return pandoc.Div({}, pandoc.Attr(id))
end

local jobs_done = false

local function ensure_jobs_done()
  if jobs_done or #pending == 0 then return end
  -- Launch all render commands in parallel within one shell, then wait
  local parts = {}
  for _, job in ipairs(pending) do
    table.insert(parts, "(" .. job.cmd .. ") &")
  end
  table.insert(parts, "wait")
  os.execute(table.concat(parts, " "))
  -- Clean up temp input files
  for _, job in ipairs(pending) do
    if job.cleanup then
      for _, f in ipairs(job.cleanup) do os.remove(f) end
    end
  end
  jobs_done = true
end

local function par_pass2_Div(div)
  ensure_jobs_done()
  local id = div.identifier
  for _, job in ipairs(pending) do
    if job.id == id then
      return pandoc.Para{pandoc.Image({pandoc.Str(job.caption)}, job.outfile)}
    end
  end
end

------------------------------------------------------------------------
-- Return filter(s)
------------------------------------------------------------------------

if parallel then
  return {
    {CodeBlock = par_pass1_CodeBlock},
    {Div = par_pass2_Div}
  }
else
  return {{CodeBlock = seq_CodeBlock}}
end
