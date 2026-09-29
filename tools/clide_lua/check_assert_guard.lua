-- Checks that every `assert` in PlantUML is guarded by TeaVM.a().
--
-- The two accepted forms (repository convention):
--   1) if (TeaVM.a()) assert x;            -- on a single line
--   2) if (TeaVM.a())                      -- guard alone on line L-1
--          assert x;                       -- assert on line L
--
-- Limits: clide's Lua has no `io`, and search_regex only returns the matching
-- line. The script therefore never sees the surrounding context: an `assert`
-- guarded by a block `if (TeaVM.a()) { ... }` is reported (intended: that is
-- not the repository convention).

local ROOT = "src/main/java"

set_max_results(10000)   -- otherwise results are truncated at 100: we would read a subset

-- Lua has no \b: use explicit word boundaries (frontier pattern).
local function has_assert(text)
  return text:find("%f[%w_]assert%f[^%w_]") ~= nil
end

-- True if this occurrence of `assert` is inside a comment or a string.
local function is_noise(text)
  local pos = text:find("%f[%w_]assert%f[^%w_]")
  local before = text:sub(1, pos - 1)
  if before:find("//", 1, true) then return true end          -- // comment
  if before:match("^%s*/?%*") then return true end            -- /* or * comment
  local _, quotes = before:gsub('"', "")
  if quotes % 2 == 1 then return true end                     -- inside a string
  return false
end

-- 1) All lines containing "assert" and all standalone guards.
local asserts = search_regex(ROOT, "\\.java$", "\\bassert\\b")
local guards  = search_regex(ROOT, "\\.java$", "^\\s*if \\(TeaVM\\.a\\(\\)\\)\\s*$")

-- 2) Index of standalone guards: "path:line" -> true.
local guard_at = {}
for _, g in ipairs(guards.matches.items) do
  guard_at[g.path .. ":" .. g.line] = true
end

if asserts.matches.truncated or guards.matches.truncated then
  error("results truncated: audit not reliable")
end

-- 3) Classification.
local total, ok_inline, ok_prev, ignored = 0, 0, 0, 0
local bad = {}
for _, m in ipairs(asserts.matches.items) do
  if not has_assert(m.text) or is_noise(m.text) then
    ignored = ignored + 1
  elseif m.path:find("/teavm/TeaVM%.java$") then
    ignored = ignored + 1     -- the javadoc of TeaVM.a() itself
  else
    total = total + 1
    if m.text:find("if%s*%(TeaVM%.a%(%)%)%s+assert%f[^%w_]") then
      ok_inline = ok_inline + 1
    elseif guard_at[m.path .. ":" .. (m.line - 1)] then
      ok_prev = ok_prev + 1
    else
      table.insert(bad, m)
    end
  end
end

-- 4) Orphan guards: a standalone `if (TeaVM.a())` whose next line is not an assert.
local next_is_assert = {}
for _, m in ipairs(asserts.matches.items) do
  next_is_assert[m.path .. ":" .. m.line] = true
end
local orphans = {}
for _, g in ipairs(guards.matches.items) do
  if not next_is_assert[g.path .. ":" .. (g.line + 1)] then
    table.insert(orphans, g)
  end
end

print(string.format("%d assert(s) examined: %d guarded inline, %d guarded on the previous line, %d NOT GUARDED  (%d lines ignored: comments/strings)",
    total, ok_inline, ok_prev, #bad, ignored))
for _, m in ipairs(bad) do
  print(string.format("  NOT GUARDED  %s:%d: %s", m.path, m.line, (m.text:gsub("^%s+", ""))))
end
if #orphans > 0 then
  print(string.format("%d `if (TeaVM.a())` guard(s) whose next line is not an assert:", #orphans))
  for _, g in ipairs(orphans) do
    print(string.format("  ORPHAN GUARD  %s:%d", g.path, g.line))
  end
end
