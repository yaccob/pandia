-- Pandoc Lua filter: renders diagram code blocks to images
-- Supported: plantuml, graphviz/dot, mermaid, ditaa, tikz
-- LaTeX math is handled natively by pandoc
--
-- For PDF output: vector graphics (PDF) where possible, PNG only for ditaa
-- For HTML output: SVG where possible, PNG for ditaa and tikz
--
-- Set PANDIA_PARALLEL=1 to render diagrams in parallel
--
-- PlantUML and ditaa diagrams are batched into single JVM calls regardless
-- of parallel mode, avoiding repeated JVM startup overhead.

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
-- Prepare functions: write input files, return job metadata
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
    return {
      tool = "plantuml",
      infile = infile,
      outfile = basename .. ".svg",
      cleanup = {infile},
    }
  else
    local svgfile = basename .. ".svg"
    return {
      tool = "plantuml",
      infile = infile,
      outfile = basename .. ".pdf",
      svgfile = svgfile,
      cleanup = {infile, svgfile},
    }
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
    return {
      tool = "graphviz",
      outfile = outfile,
      cmd = engine .. " -Tsvg -o " .. outfile .. " " .. infile,
      cleanup = {infile},
    }
  else
    local outfile = basename .. ".pdf"
    return {
      tool = "graphviz",
      outfile = outfile,
      cmd = engine .. " -Tpdf -o " .. outfile .. " " .. infile,
      cleanup = {infile},
    }
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
    return {
      tool = "mermaid",
      outfile = outfile,
      cmd = "mmdc -i " .. infile .. " -o " .. outfile .. mmdc_extra .. " --quiet 2>/dev/null",
      cleanup = {infile},
    }
  else
    local outfile = basename .. ".pdf"
    return {
      tool = "mermaid",
      outfile = outfile,
      cmd = "mmdc -i " .. infile .. " -o " .. outfile .. mmdc_extra .. " --quiet 2>/dev/null",
      cleanup = {infile},
    }
  end
end

local function prepare_ditaa(code)
  ensure_imgdir()
  filecounter = filecounter + 1
  local basename = imgdir .. "/ditaa-" .. filecounter
  local wrapped = "@startditaa\n" .. code .. "\n@endditaa"
  local infile = basename .. ".puml"
  local f = io.open(infile, "w")
  f:write(wrapped)
  f:close()

  return {
    tool = "ditaa",
    infile = infile,
    outfile = basename .. ".png",
    cleanup = {infile},
  }
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
    return {
      tool = "tikz",
      outfile = pngfile,
      cmd = compile
        .. " && gs -sDEVICE=pngalpha -r300 -dNOPAUSE -dBATCH -dQUIET"
        .. " -sOutputFile=" .. pngfile .. " " .. pdffile .. " 2>/dev/null",
      cleanup = cleanup,
    }
  else
    return {
      tool = "tikz",
      outfile = pdffile,
      cmd = compile,
      cleanup = cleanup,
    }
  end
end

------------------------------------------------------------------------
-- Pass 1: collect all diagram blocks, write input files
------------------------------------------------------------------------

local pending = {}

local function pass1_CodeBlock(block)
  detect_format()
  local lang = block.classes[1]
  local caption = block.attributes.caption or ""

  local job = nil
  if lang == "plantuml" then
    job = prepare_plantuml(block.text)
  elseif lang == "graphviz" or lang == "dot" then
    job = prepare_graphviz(block.text, block.attributes.engine)
  elseif lang == "mermaid" then
    job = prepare_mermaid(block.text)
  elseif lang == "ditaa" then
    job = prepare_ditaa(block.text)
  elseif lang == "tikz" then
    job = prepare_tikz(block.text)
  end

  if not job then return nil end

  job.caption = caption
  job.id = "pandia-job-" .. (#pending + 1)
  table.insert(pending, job)
  return pandoc.Div({}, pandoc.Attr(job.id))
end

------------------------------------------------------------------------
-- Execution: batch plantuml/ditaa, run others individually or parallel
------------------------------------------------------------------------

local jobs_done = false

local function execute_all()
  if jobs_done or #pending == 0 then return end

  -- Collect plantuml and ditaa files for batching
  local puml_files = {}
  local puml_jobs = {}
  for _, job in ipairs(pending) do
    if job.tool == "plantuml" then
      table.insert(puml_files, job.infile)
      table.insert(puml_jobs, job)
    end
  end

  local ditaa_files = {}
  for _, job in ipairs(pending) do
    if job.tool == "ditaa" then
      table.insert(ditaa_files, job.infile)
    end
  end

  -- Collect individual commands (graphviz, mermaid, tikz)
  local other_cmds = {}
  for _, job in ipairs(pending) do
    if job.cmd then
      table.insert(other_cmds, job.cmd)
    end
  end

  if parallel then
    -- All tool groups run concurrently
    local parts = {}

    -- PlantUML batch as one background job (one JVM)
    if #puml_files > 0 then
      local puml_cmd = "plantuml -tsvg " .. table.concat(puml_files, " ")
      if is_pdf then
        -- Chain SVG→PDF conversions after plantuml finishes
        for _, job in ipairs(puml_jobs) do
          puml_cmd = puml_cmd
            .. " && rsvg-convert -f pdf -o " .. job.outfile .. " " .. job.svgfile
        end
      end
      table.insert(parts, "(" .. puml_cmd .. ") &")
    end

    -- Ditaa batch as one background job (one JVM)
    if #ditaa_files > 0 then
      table.insert(parts, "(plantuml -tpng " .. table.concat(ditaa_files, " ") .. ") &")
    end

    -- Each other tool as its own background job
    for _, cmd in ipairs(other_cmds) do
      table.insert(parts, "(" .. cmd .. ") &")
    end

    table.insert(parts, "wait")
    os.execute(table.concat(parts, " "))
  else
    -- Sequential: still batch plantuml/ditaa (one JVM each)
    if #puml_files > 0 then
      os.execute("plantuml -tsvg " .. table.concat(puml_files, " "))
      if is_pdf then
        for _, job in ipairs(puml_jobs) do
          os.execute("rsvg-convert -f pdf -o " .. job.outfile .. " " .. job.svgfile)
        end
      end
    end

    if #ditaa_files > 0 then
      os.execute("plantuml -tpng " .. table.concat(ditaa_files, " "))
    end

    for _, cmd in ipairs(other_cmds) do
      os.execute(cmd)
    end
  end

  -- Clean up temp files
  for _, job in ipairs(pending) do
    if job.cleanup then
      for _, f in ipairs(job.cleanup) do os.remove(f) end
    end
  end

  jobs_done = true
end

------------------------------------------------------------------------
-- Pass 2: replace placeholders with rendered images
------------------------------------------------------------------------

local function pass2_Div(div)
  execute_all()
  local id = div.identifier
  for _, job in ipairs(pending) do
    if job.id == id then
      return pandoc.Para{pandoc.Image({pandoc.Str(job.caption)}, job.outfile)}
    end
  end
end

------------------------------------------------------------------------
-- Return two-pass filter
------------------------------------------------------------------------

return {
  {CodeBlock = pass1_CodeBlock},
  {Div = pass2_Div}
}
