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

-- Ensure an SVG has a white background. Injects a white rect as the first
-- child of the root <svg>, so diagram content (rendered later) draws on top.
local function ensure_svg_background(svg)
  if not svg then return svg end
  local vb = svg:match('viewBox="([^"]+)"')
  local bg_rect
  if vb then
    local x, y, w, h = vb:match("([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)")
    if x and y and w and h then
      bg_rect = string.format('<rect x="%s" y="%s" width="%s" height="%s" fill="white"/>', x, y, w, h)
    end
  end
  if not bg_rect then
    local w = svg:match('width="([^"]+)"')
    local h = svg:match('height="([^"]+)"')
    if w and h then
      bg_rect = string.format('<rect width="%s" height="%s" fill="white"/>', w, h)
    else
      bg_rect = '<rect width="100%%" height="100%%" fill="white"/>'
    end
  end
  return svg:gsub('(<svg[^>]*>)', '%1\n' .. bg_rect, 1)
end

-- Local tool types (rendered without Kroki)
local local_tools = {
  plantuml = true, graphviz = true, dot = true,
  mermaid = true, ditaa = true, tikz = true,
  markmap = true,
}

-- Types rendered via diagram-renderer.mjs (Node.js npm packages)
local node_renderer_types = {
  nomnoml = true, dbml = true, d2 = true, wavedrom = true,
}

-- Path to diagram-renderer.mjs (resolve: env var, container path, relative to filter)
-- Must be declared before node_renderer_available() which references it.
local diagram_renderer = os.getenv("PANDIA_DIAGRAM_RENDERER")
local function file_readable(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end
if not diagram_renderer then
  local candidates = {
    "/usr/local/lib/node_modules/diagram-renderer.mjs",
    "/usr/local/share/pandia/diagram-renderer.mjs",
  }
  -- Also try relative to this filter's directory
  local script_dir = debug.getinfo(1, "S").source:match("@?(.*/)") or ""
  table.insert(candidates, script_dir .. "diagram-renderer.mjs")
  for _, path in ipairs(candidates) do
    if file_readable(path) then diagram_renderer = path; break end
  end
end

-- Check if a node_renderer_type can actually run locally
local node_renderer_avail_cache = {}
local function node_renderer_available(dtype)
  if node_renderer_avail_cache[dtype] ~= nil then
    return node_renderer_avail_cache[dtype]
  end
  local avail = false
  if dtype == "d2" then
    avail = os.execute("d2 --version >/dev/null 2>&1") == true
  else
    avail = diagram_renderer ~= nil
  end
  node_renderer_avail_cache[dtype] = avail
  return avail
end

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

-- Detect best available tool for TikZ PDF→SVG conversion (once at startup)
-- Priority: dvisvgm (TeX Live, works everywhere), pdftocairo (poppler-utils,
-- container), pdf2svg (standalone). dvisvgm before pdftocairo because
-- pdftocairo can crash on macOS due to broken poppler library dependencies.
local tikz_svg_tool = nil
if os.execute("which dvisvgm >/dev/null 2>&1") then
  tikz_svg_tool = "dvisvgm"
elseif os.execute("which pdftocairo >/dev/null 2>&1") then
  tikz_svg_tool = "pdftocairo"
elseif os.execute("which pdf2svg >/dev/null 2>&1") then
  tikz_svg_tool = "pdf2svg"
end

local function detect_format()
  is_html = FORMAT:match("html") ~= nil
  is_pdf = not is_html
end

------------------------------------------------------------------------
-- Prepare functions: write input files, return job metadata
------------------------------------------------------------------------

local function prepare_plantuml(code)
  -- Wrap in @startuml/@enduml if no @start tag present
  if not code:match("^%s*@start") then
    code = "@startuml\n" .. code .. "\n@enduml"
  end

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
    .. " " .. texfile .. " >/dev/null"
  local cleanup = {texfile, basename .. ".aux", basename .. ".log"}

  if is_html then
    -- Prefer SVG (vector) via dvisvgm or pdf2svg; fall back to PNG via gs
    local svgfile = basename .. ".svg"
    local pngfile = basename .. ".png"
    local pdf2svg_cmd
    if tikz_svg_tool == "pdftocairo" then
      pdf2svg_cmd = compile .. " || { rm -f " .. pdffile .. "; false; }"
        .. " && pdftocairo -svg " .. pdffile .. " " .. svgfile
    elseif tikz_svg_tool == "dvisvgm" then
      -- dvisvgm needs libgs for TikZ PostScript specials; use latex→DVI path
      local dvifile = basename .. ".dvi"
      local compile_dvi = "latex -interaction=nonstopmode -output-directory=" .. imgdir
        .. " " .. texfile .. " >/dev/null 2>&1"
      table.insert(cleanup, dvifile)
      local libgs_flag = ""
      local libgs = os.getenv("LIBGS")
      if not libgs then
        local candidates = {
          "/opt/homebrew/lib/libgs.dylib", "/opt/homebrew/lib/libgs.10.dylib",
          "/usr/lib/libgs.so", "/usr/lib/libgs.so.10",
          "/usr/local/lib/libgs.dylib", "/usr/local/lib/libgs.so",
        }
        for _, p in ipairs(candidates) do
          if file_readable(p) then libgs = p; break end
        end
      end
      if libgs then libgs_flag = " --libgs=" .. libgs end
      pdf2svg_cmd = compile_dvi .. " || { rm -f " .. dvifile .. "; false; }"
        .. " && dvisvgm" .. libgs_flag .. " --no-fonts --exact-bbox -o " .. svgfile .. " " .. dvifile
    elseif tikz_svg_tool == "pdf2svg" then
      pdf2svg_cmd = compile .. " || { rm -f " .. pdffile .. "; false; }"
        .. " && pdf2svg " .. pdffile .. " " .. svgfile
    end
    if pdf2svg_cmd then
      return {
        tool = "tikz",
        outfile = svgfile,
        cmd = pdf2svg_cmd,
        cleanup = cleanup,
      }
    end
    -- Fallback: PNG via Ghostscript (raster, but works everywhere)
    return {
      tool = "tikz",
      outfile = pngfile,
      cmd = compile .. " || { rm -f " .. pdffile .. "; false; }"
        .. " && gs -sDEVICE=png16m -r300 -dNOPAUSE -dBATCH -dQUIET"
        .. " -sOutputFile=" .. pngfile .. " " .. pdffile,
      cleanup = cleanup,
    }
  else
    return {
      tool = "tikz",
      outfile = pdffile,
      cmd = compile .. " || { rm -f " .. pdffile .. "; false; }",
      cleanup = cleanup,
    }
  end
end

------------------------------------------------------------------------
-- Directory tree rendering (SVG for both HTML and PDF)
------------------------------------------------------------------------

local function render_dir(code)
  -- Collect non-empty lines
  local lines = {}
  for line in code:gmatch("[^\n]*") do
    if line:match("%S") then
      table.insert(lines, line)
    end
  end
  if #lines == 0 then return nil, "Empty dir block" end

  -- Baseline indent from first non-empty line
  local baseline = #(lines[1]:match("^(%s*)"))

  -- Indent unit from first line that is deeper than baseline
  local indent_unit = nil
  for i = 2, #lines do
    local rel = #(lines[i]:match("^(%s*)")) - baseline
    if rel > 0 then
      indent_unit = rel
      break
    end
  end
  indent_unit = indent_unit or 2

  -- Parse entries with level and validation
  local entries = {}
  for i, line in ipairs(lines) do
    local spaces = #(line:match("^(%s*)"))
    local name = line:match("^%s*(.+)$")
    local rel = spaces - baseline

    if rel < 0 then
      return nil, "Line " .. i .. " ('" .. name .. "'): indentation is less than the root"
    end
    if rel > 0 and rel % indent_unit ~= 0 then
      return nil, "Line " .. i .. " ('" .. name .. "'): inconsistent indentation ("
        .. rel .. " spaces, expected multiple of " .. indent_unit .. ")"
    end

    local level = (rel > 0) and (rel / indent_unit) or 0

    -- Validate: level can increase by at most 1
    if #entries > 0 and level > entries[#entries].level + 1 then
      return nil, "Line " .. i .. " ('" .. name .. "'): indentation jumps by more than one level"
    end

    table.insert(entries, {name = name, level = level})
  end

  -- Determine is_dir: has children, or trailing /
  for i = 1, #entries do
    entries[i].is_dir = entries[i].name:match("/$") ~= nil
    if i < #entries and entries[i+1].level > entries[i].level then
      entries[i].is_dir = true
    end
  end

  -- Strip trailing / from display names (after is_dir detection)
  for i = 1, #entries do
    entries[i].display = entries[i].name:gsub("/$", "")
  end

  -- SVG layout constants
  local font_size = 14
  local line_height = 18
  local char_width = 8.4
  local pad_x = 6
  local pad_y = 2
  local trunk_offset = 3     -- trunk x relative to parent text start
  local connector_len = 14   -- horizontal connector length
  local connector_gap = 4    -- gap between connector end and text
  local indent_step = trunk_offset + connector_len + connector_gap

  -- x position of the vertical trunk for children at a given level
  local function get_trunk_x(child_level)
    return pad_x + trunk_offset + (child_level - 1) * indent_step
  end

  -- x position where text starts for a given level
  local function get_text_x(level)
    if level == 0 then return pad_x end
    return get_trunk_x(level) + connector_len + connector_gap
  end

  -- y center of a row (1-based index), used for connectors
  local function y_mid(idx)
    return pad_y + (idx - 0.5) * line_height
  end

  -- y baseline for text rendering (align text vertically centered in row)
  local function y_base(idx)
    return pad_y + (idx - 0.5) * line_height + font_size * 0.35
  end

  -- y position just below a row's text (start of vertical trunk)
  local function y_below(idx)
    return pad_y + idx * line_height
  end

  -- Collect SVG elements
  local svg_elems = {}
  local max_text_end = 0

  -- Text elements
  for i, entry in ipairs(entries) do
    local tx = get_text_x(entry.level)
    local escaped = entry.display:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    local weight = entry.is_dir and ' font-weight="bold"' or ""
    table.insert(svg_elems, '<text x="' .. tx .. '" y="' .. y_base(i)
      .. '"' .. weight .. '>' .. escaped .. '</text>')
    local text_end = tx + #entry.display * char_width
    if text_end > max_text_end then max_text_end = text_end end
  end

  -- Horizontal connectors for non-root entries
  for i, entry in ipairs(entries) do
    if entry.level > 0 then
      local tx = get_trunk_x(entry.level)
      local ym = y_mid(i)
      table.insert(svg_elems, '<line x1="' .. tx .. '" y1="' .. ym
        .. '" x2="' .. (tx + connector_len) .. '" y2="' .. ym .. '"/>')
    end
  end

  -- Vertical trunk lines: for each parent, draw from just below
  -- the parent row down to the last child's y_mid
  for i, entry in ipairs(entries) do
    local last_child = nil
    for j = i + 1, #entries do
      if entries[j].level <= entry.level then break end
      if entries[j].level == entry.level + 1 then
        last_child = j
      end
    end
    if last_child then
      local tx = get_trunk_x(entry.level + 1)
      table.insert(svg_elems, '<line x1="' .. tx .. '" y1="' .. y_below(i)
        .. '" x2="' .. tx .. '" y2="' .. y_mid(last_child) .. '"/>')
    end
  end

  -- Assemble SVG
  local width = math.ceil(max_text_end) + pad_x
  local height = #entries * line_height + 2 * pad_y

  local svg = {
    '<svg xmlns="http://www.w3.org/2000/svg"'
      .. ' width="' .. width .. '" height="' .. height .. '"'
      .. ' viewBox="0 0 ' .. width .. ' ' .. height .. '">',
    '<style>'
      .. 'text { font-family: "Courier New", Courier, monospace;'
      .. ' font-size: ' .. font_size .. 'px; }'
      .. ' line { stroke: #000; stroke-width: 1.2; }'
      .. '</style>',
  }
  for _, elem in ipairs(svg_elems) do
    table.insert(svg, elem)
  end
  table.insert(svg, '</svg>')
  local svg_str = ensure_svg_background(table.concat(svg, "\n"))

  if is_html then
    return pandoc.RawBlock("html", svg_str)
  else
    -- Write SVG and convert to PDF via rsvg-convert
    ensure_imgdir()
    filecounter = filecounter + 1
    local basename = imgdir .. "/dir-" .. filecounter
    local svgfile = basename .. ".svg"
    local pdffile = basename .. ".pdf"
    local f = io.open(svgfile, "w")
    f:write(svg_str)
    f:close()
    local ok = os.execute("rsvg-convert -f pdf -o " .. pdffile .. " " .. svgfile)
    os.remove(svgfile)
    if not ok then
      io.stderr:write("pandia dir error: rsvg-convert failed for " .. pdffile .. "\n")
      return pandoc.Para{pandoc.Strong{pandoc.Str("dir error: rsvg-convert failed")}}
    end
    return pandoc.Para{pandoc.Image({}, pdffile)}
  end
end

------------------------------------------------------------------------
-- Markmap rendering: interactive HTML or static PNG
------------------------------------------------------------------------

-- Locate the markmap-render.mjs helper script
local function find_markmap_render()
  for _, dir in ipairs({
    -- Beside the filter (dev / Homebrew)
    PANDOC_SCRIPT_FILE and PANDOC_SCRIPT_FILE:match("(.*/)")  or "",
    -- Container location
    "/usr/local/share/pandia/",
  }) do
    local path = dir .. "markmap-render.mjs"
    local f = io.open(path, "r")
    if f then f:close(); return path end
  end
  return nil
end

local markmap_counter = 0

local function render_markmap_html(code)
  if not code:match("%S") then
    return nil, "Empty markmap block"
  end

  local render_script = find_markmap_render()
  if not render_script then
    return nil, "markmap-render.mjs not found"
  end

  ensure_imgdir()
  markmap_counter = markmap_counter + 1
  local id = markmap_counter
  local infile = imgdir .. "/markmap-" .. id .. ".md"
  local outfile = imgdir .. "/markmap-" .. id .. ".html"

  local f = io.open(infile, "w")
  f:write(code)
  f:close()

  local cmd = "node " .. render_script
    .. " --input " .. infile
    .. " --output " .. outfile
    .. " --format html-fragment"
    .. " --id " .. id

  local ok = os.execute(cmd .. " 2>/dev/null")
  local result = nil
  if ok then
    local out = io.open(outfile, "r")
    if out then
      local content = out:read("*a")
      out:close()
      result = pandoc.RawBlock("html", ensure_svg_background(content))
    end
  end

  os.remove(infile)
  os.remove(outfile)

  if result then
    return result
  end
  return nil, "markmap-render.mjs failed"
end

local function prepare_markmap_pdf(code)
  local render_script = find_markmap_render()
  if not render_script then return nil end

  ensure_imgdir()
  filecounter = filecounter + 1
  local basename = imgdir .. "/markmap-" .. filecounter
  local infile = basename .. ".md"
  local outfile = basename .. ".pdf"

  local f = io.open(infile, "w")
  f:write(code)
  f:close()

  -- Render to vector PDF via headless browser (Chromium page.pdf())
  local cmd = "node " .. render_script
    .. " --input " .. infile
    .. " --output " .. outfile
    .. " --format pdf"
    .. " --id " .. filecounter

  return {
    tool = "markmap",
    outfile = outfile,
    cmd = cmd,
    cleanup = {infile},
  }
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
-- Node.js diagram-renderer.mjs (nomnoml, dbml, d2, wavedrom)
------------------------------------------------------------------------

local function prepare_node_renderer(code, diagram_type)
  ensure_imgdir()
  filecounter = filecounter + 1

  local basename = imgdir .. "/" .. diagram_type .. "-" .. filecounter
  local infile = basename .. ".txt"
  local svgfile = basename .. ".svg"

  local f = io.open(infile, "w")
  f:write(code)
  f:close()

  local cmd = "node " .. diagram_renderer
    .. " --type " .. diagram_type
    .. " --input " .. infile
    .. " --output " .. svgfile

  if is_html then
    return {
      tool = diagram_type,
      outfile = svgfile,
      cmd = cmd,
      cleanup = {infile},
    }
  else
    local outfile = basename .. ".pdf"
    return {
      tool = diagram_type,
      outfile = outfile,
      cmd = cmd
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

  -- Directory tree (pure text, no external tool)
  if lang == "dir" then
    detect_format()
    local result, err = render_dir(block.text)
    if err then
      io.stderr:write("pandia dir error: " .. err .. "\n")
      return pandoc.Para{pandoc.Strong{pandoc.Str("dir error: " .. err)}}
    end
    return result
  end

  -- Markmap: interactive HTML or static PNG (like dir blocks)
  if lang == "markmap" then
    detect_format()
    if is_html then
      local result, err = render_markmap_html(block.text)
      if err then
        io.stderr:write("pandia markmap error: " .. err .. "\n")
        return pandoc.Para{pandoc.Strong{pandoc.Str("markmap error: " .. err)}}
      end
      return result
    else
      job = prepare_markmap_pdf(block.text)
    end
  -- Local tools take priority
  elseif lang == "plantuml" then
    job = prepare_plantuml(block.text)
  elseif lang == "graphviz" or lang == "dot" then
    job = prepare_graphviz(block.text, block.attributes.engine)
  elseif lang == "mermaid" then
    job = prepare_mermaid(block.text)
  elseif lang == "ditaa" then
    job = prepare_ditaa(block.text)
  elseif lang == "tikz" then
    job = prepare_tikz(block.text)
  elseif node_renderer_types[lang] and node_renderer_available(lang) then
    job = prepare_node_renderer(block.text, lang)
  elseif kroki_server and kroki_types[lang] then
    -- Not available locally but supported by Kroki
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

-- Resolve a path to absolute (needed when mermaid server has different CWD)
local function abspath(path)
  if path:sub(1, 1) == "/" then return path end
  local pipe = io.popen("pwd")
  local cwd = pipe:read("*l")
  pipe:close()
  return cwd .. "/" .. path
end

local function execute_mermaid_server(mermaid_jobs)
  local parts = {}
  for _, job in ipairs(mermaid_jobs) do
    parts[#parts + 1] = "(wget -q -O /dev/null '"
      .. mermaid_server .. "/render?in=" .. abspath(job.infile)
      .. "&out=" .. abspath(job.outfile) .. "&fmt=" .. job.fmt .. "') &"
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

  -- Assign errfile and rcfile to each job for capturing tool stderr and exit code
  for _, job in ipairs(pending) do
    local base = job.outfile:gsub("%.[^.]+$", "")
    job.errfile = base .. ".err"
    job.rcfile = base .. ".rc"
  end

  -- Collect jobs by tool
  local puml_files = {}
  local puml_jobs = {}
  local ditaa_files = {}
  local ditaa_jobs = {}
  local mermaid_jobs = {}
  local other_jobs = {}

  for _, job in ipairs(pending) do
    if job.tool == "plantuml" then
      table.insert(puml_files, job.infile)
      table.insert(puml_jobs, job)
    elseif job.tool == "ditaa" then
      table.insert(ditaa_files, job.infile)
      table.insert(ditaa_jobs, job)
    elseif job.tool == "mermaid" then
      table.insert(mermaid_jobs, job)
    elseif job.cmd then
      table.insert(other_jobs, job)
    end
  end

  -- Build parallel shell command
  local parts = {}

  -- PlantUML batch as one background job (one JVM)
  if #puml_files > 0 then
    local errfile = puml_jobs[1].errfile
    local rcfile = puml_jobs[1].rcfile
    local puml_cmd = "plantuml -tsvg " .. table.concat(puml_files, " ")
    -- PlantUML emits preserveAspectRatio="none" which prevents proportional
    -- scaling in browsers. Remove it so SVGs scale correctly.
    for _, job in ipairs(puml_jobs) do
      local svg = job.svgfile or job.outfile
      puml_cmd = puml_cmd
        .. " && sed 's/ preserveAspectRatio=\"none\"//g' " .. svg .. " > " .. svg .. ".tmp"
        .. " && mv " .. svg .. ".tmp " .. svg
    end
    if is_pdf then
      for _, job in ipairs(puml_jobs) do
        puml_cmd = puml_cmd
          .. " && rsvg-convert -f pdf -o " .. job.outfile .. " " .. job.svgfile
      end
    end
    table.insert(parts, "(" .. puml_cmd .. " 2>" .. errfile
      .. "; echo $? >" .. rcfile .. ") &")
    for _, job in ipairs(puml_jobs) do
      job.errfile = errfile
      job.rcfile = rcfile
    end
  end

  -- Ditaa batch as one background job (one JVM)
  if #ditaa_files > 0 then
    local errfile = ditaa_jobs[1].errfile
    local rcfile = ditaa_jobs[1].rcfile
    table.insert(parts, "(plantuml -tpng " .. table.concat(ditaa_files, " ")
      .. " 2>" .. errfile .. "; echo $? >" .. rcfile .. ") &")
    for _, job in ipairs(ditaa_jobs) do
      job.errfile = errfile
      job.rcfile = rcfile
    end
  end

  -- Each other tool (graphviz, tikz, kroki) as its own background job
  for _, job in ipairs(other_jobs) do
    table.insert(parts, "(" .. job.cmd .. " 2>" .. job.errfile
      .. "; echo $? >" .. job.rcfile .. ") &")
  end

  -- Mermaid batch via mmdc (one Chromium, as background job)
  if #mermaid_jobs > 0 and not mermaid_server then
    local batchfile = imgdir .. "/mermaid-batch.md"
    local outbase = imgdir .. "/mermaid-out"
    local fmt = mermaid_jobs[1].fmt
    local errfile = mermaid_jobs[1].errfile
    local rcfile = mermaid_jobs[1].rcfile
    local f = io.open(batchfile, "w")
    for _, job in ipairs(mermaid_jobs) do
      f:write("```mermaid\n" .. job.code .. "\n```\n\n")
    end
    f:close()
    local mmdc_cmd = "mmdc -i " .. batchfile .. " -o " .. outbase .. ".md -e " .. fmt
      .. mmdc_extra .. " --quiet"
    table.insert(parts, "(" .. mmdc_cmd .. " 2>" .. errfile
      .. "; echo $? >" .. rcfile .. ") &")
    for _, job in ipairs(mermaid_jobs) do
      job.errfile = errfile
      job.rcfile = rcfile
    end
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

  -- Clean up temp files (but keep errfiles for pass2)
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

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

local function pass2_Div(div)
  execute_all()
  local id = div.identifier
  for _, job in ipairs(pending) do
    if job.id == id then
      -- Read and clean up errfile and rcfile
      local errtext = job.errfile and read_file(job.errfile)
      local rctext = job.rcfile and read_file(job.rcfile)
      if job.errfile then os.remove(job.errfile) end
      if job.rcfile then os.remove(job.rcfile) end

      local rc = rctext and tonumber(rctext:match("%d+")) or 0

      if rc == 0 and file_exists(job.outfile) then
        -- Ensure SVG diagrams have a white background
        if job.outfile:match("%.svg$") then
          local svg = read_file(job.outfile)
          if svg then
            local patched = ensure_svg_background(svg)
            if patched ~= svg then
              local f = io.open(job.outfile, "w")
              if f then f:write(patched); f:close() end
            end
          end
        end
        return pandoc.Para{pandoc.Image({pandoc.Str(job.caption)}, job.outfile)}
      end

      -- Build helpful error message from tool stderr
      local detail = ""
      if errtext and errtext:match("%S") then
        local lines = {}
        for line in errtext:gmatch("[^\n]+") do
          if #lines < 5 then table.insert(lines, line) end
        end
        detail = ": " .. table.concat(lines, "; ")
      end

      local msg = "pandia " .. job.tool .. " error: rendering failed" .. detail
      io.stderr:write(msg .. "\n")
      return pandoc.Para{pandoc.Strong{pandoc.Str(msg)}}
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
