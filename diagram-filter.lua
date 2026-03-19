-- Pandoc Lua filter: renders diagram code blocks to images
-- Supported locally: plantuml, graphviz/dot, mermaid, ditaa, tikz
-- With --kroki: additionally all Kroki-supported types (d2, bpmn, etc.)
-- LaTeX math is handled natively by pandoc
--
-- For PDF output: vector graphics (PDF) where possible, PNG only for ditaa
-- For HTML output: SVG where possible, PNG for ditaa and tikz
--
-- All diagram tool groups run concurrently. PlantUML, ditaa, and mermaid
-- diagrams are batched to avoid repeated JVM/Chromium startup overhead.
-- Set MERMAID_SERVER=http://host:port to use a persistent render server
-- instead of mmdc batch mode (used in container for watch mode).

local filecounter = 0
local imgdir = "img"
local is_html = false
local is_pdf = false

-- Optional puppeteer config for mermaid (needed in containers)
local mmdc_puppeteer = os.getenv("MMDC_PUPPETEER_CONFIG")
local mmdc_extra = mmdc_puppeteer and (" -p " .. mmdc_puppeteer) or ""

-- Optional mermaid server (container mode)
local mermaid_server = os.getenv("MERMAID_SERVER")

-- Kroki server (set via --kroki / --kroki-server)
local kroki_server = os.getenv("PANDIA_KROKI_URL")

-- Local tool types (rendered without Kroki)
local local_tools = {
  plantuml = true, graphviz = true, dot = true,
  mermaid = true, ditaa = true, tikz = true,
}

-- All Kroki-supported diagram types
local kroki_types = {
  actdiag = true, blockdiag = true, bpmn = true, bytefield = true,
  c4plantuml = true, d2 = true, dbml = true, ditaa = true,
  erd = true, excalidraw = true, graphviz = true, dot = true,
  mermaid = true, nomnoml = true, nwdiag = true, packetdiag = true,
  pikchr = true, plantuml = true, rackdiag = true, seqdiag = true,
  structurizr = true, svgbob = true, symbolator = true, tikz = true,
  vega = true, vegalite = true, wavedrom = true, wireviz = true,
}

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
    local svgfile = basename .. ".svg"
    local outfile = basename .. ".pdf"
    return {
      tool = "graphviz",
      outfile = outfile,
      cmd = engine .. " -Tsvg -o " .. svgfile .. " " .. infile
        .. " && rsvg-convert -f pdf -o " .. outfile .. " " .. svgfile,
      cleanup = {infile, svgfile},
    }
  end
end

local function prepare_mermaid(code)
  ensure_imgdir()
  filecounter = filecounter + 1
  local basename = imgdir .. "/mermaid-" .. filecounter
  local fmt = is_html and "svg" or "pdf"

  return {
    tool = "mermaid",
    code = code,
    outfile = basename .. "." .. fmt,
    fmt = fmt,
  }
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

  -- Extract \usepackage and \usetikzlibrary lines into preamble
  local preamble = {}
  local body_lines = {}
  for line in code:gmatch("[^\n]+") do
    if line:match("^%s*\\usepackage") or line:match("^%s*\\usetikzlibrary") then
      table.insert(preamble, line)
    else
      table.insert(body_lines, line)
    end
  end
  local body = table.concat(body_lines, "\n")

  local doc = "\\documentclass[tikz,border=2pt]{standalone}\n"
  if #preamble > 0 then
    doc = doc .. table.concat(preamble, "\n") .. "\n"
  end
  if not body:match("\\begin{tikzpicture}") then
    doc = doc .. "\\begin{document}\n\\begin{tikzpicture}\n"
      .. body
      .. "\n\\end{tikzpicture}\n\\end{document}\n"
  else
    doc = doc .. "\\begin{document}\n" .. body .. "\n\\end{document}\n"
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
        .. "; gs -sDEVICE=pngalpha -r300 -dNOPAUSE -dBATCH -dQUIET"
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
-- Kroki rendering: POST diagram source, receive image
------------------------------------------------------------------------

local function prepare_kroki(code, diagram_type)
  ensure_imgdir()
  filecounter = filecounter + 1

  -- Map some aliases to Kroki identifiers
  local kroki_type = diagram_type
  if kroki_type == "dot" then kroki_type = "graphviz" end

  local basename = imgdir .. "/kroki-" .. filecounter
  local infile = basename .. ".txt"
  local svgfile = basename .. ".svg"

  local f = io.open(infile, "w")
  f:write(code)
  f:close()

  -- Always fetch SVG from Kroki (most types only support SVG)
  local curl_cmd = "curl -sf -X POST"
    .. " -H 'Content-Type: text/plain'"
    .. " --data-binary @" .. infile
    .. " -o " .. svgfile
    .. " '" .. kroki_server .. "/" .. kroki_type .. "/svg'"

  if is_html then
    return {
      tool = "kroki",
      outfile = svgfile,
      cmd = curl_cmd,
      cleanup = {infile},
    }
  else
    -- PDF: fetch SVG, then convert via rsvg-convert
    local outfile = basename .. ".pdf"
    return {
      tool = "kroki",
      outfile = outfile,
      cmd = curl_cmd
        .. " && rsvg-convert -f pdf -o " .. outfile .. " " .. svgfile,
      cleanup = {infile, svgfile},
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

  -- Local tools take priority
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
  elseif kroki_server and kroki_types[lang] then
    -- Unknown locally but supported by Kroki
    job = prepare_kroki(block.text, lang)
  end

  if not job then return nil end

  job.caption = caption
  job.id = "pandia-job-" .. (#pending + 1)
  table.insert(pending, job)
  return pandoc.Div({}, pandoc.Attr(job.id))
end

------------------------------------------------------------------------
-- Mermaid rendering (server mode)
------------------------------------------------------------------------

local function execute_mermaid_server(mermaid_jobs)
  local parts = {}
  for _, job in ipairs(mermaid_jobs) do
    parts[#parts + 1] = "(wget -q -O /dev/null '"
      .. mermaid_server .. "/render?in=" .. job.infile
      .. "&out=" .. job.outfile .. "&fmt=" .. job.fmt .. "') &"
  end
  parts[#parts + 1] = "wait"
  os.execute(table.concat(parts, " "))
end

------------------------------------------------------------------------
-- Execution: all tool groups run concurrently, batched where possible
------------------------------------------------------------------------

local jobs_done = false

local function execute_all()
  if jobs_done or #pending == 0 then return end

  -- Collect jobs by tool
  local puml_files = {}
  local puml_jobs = {}
  local ditaa_files = {}
  local mermaid_jobs = {}
  local other_cmds = {}

  for _, job in ipairs(pending) do
    if job.tool == "plantuml" then
      table.insert(puml_files, job.infile)
      table.insert(puml_jobs, job)
    elseif job.tool == "ditaa" then
      table.insert(ditaa_files, job.infile)
    elseif job.tool == "mermaid" then
      table.insert(mermaid_jobs, job)
    elseif job.cmd then
      table.insert(other_cmds, job.cmd)
    end
  end

  -- Build parallel shell command
  local parts = {}

  -- PlantUML batch as one background job (one JVM)
  if #puml_files > 0 then
    local puml_cmd = "plantuml -tsvg " .. table.concat(puml_files, " ")
    if is_pdf then
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

  -- Each other tool (graphviz, tikz) as its own background job
  for _, cmd in ipairs(other_cmds) do
    table.insert(parts, "(" .. cmd .. ") &")
  end

  -- Mermaid batch via mmdc (one Chromium, as background job)
  if #mermaid_jobs > 0 and not mermaid_server then
    local batchfile = imgdir .. "/mermaid-batch.md"
    local outbase = imgdir .. "/mermaid-out"
    local fmt = mermaid_jobs[1].fmt
    local f = io.open(batchfile, "w")
    for _, job in ipairs(mermaid_jobs) do
      f:write("```mermaid\n" .. job.code .. "\n```\n\n")
    end
    f:close()
    local mmdc_cmd = "mmdc -i " .. batchfile .. " -o " .. outbase .. ".md -e " .. fmt
      .. mmdc_extra .. " --quiet 2>/dev/null"
    table.insert(parts, "(" .. mmdc_cmd .. ") &")
  end

  -- Launch all background jobs and wait
  if #parts > 0 then
    table.insert(parts, "wait")
    os.execute(table.concat(parts, " "))
  end

  -- Mermaid server mode: send requests concurrently
  if #mermaid_jobs > 0 and mermaid_server then
    for _, job in ipairs(mermaid_jobs) do
      local infile = job.outfile:gsub("%.[^.]+$", ".mmd")
      local f = io.open(infile, "w")
      f:write(job.code)
      f:close()
      job.infile = infile
      job.cleanup = {infile}
    end
    execute_mermaid_server(mermaid_jobs)
  end

  -- Mermaid batch: rename outputs after wait
  if #mermaid_jobs > 0 and not mermaid_server then
    local outbase = imgdir .. "/mermaid-out"
    local fmt = mermaid_jobs[1].fmt
    for i, job in ipairs(mermaid_jobs) do
      os.rename(outbase .. "-" .. i .. "." .. fmt, job.outfile)
    end
    os.remove(imgdir .. "/mermaid-batch.md")
    os.remove(outbase .. ".md")
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
