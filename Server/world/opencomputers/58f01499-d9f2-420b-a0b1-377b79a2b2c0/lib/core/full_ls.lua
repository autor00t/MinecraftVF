local fs = require("filesystem")
local shell = require("shell")
local tty = require("tty")
local unicode = require("unicode")
local tx = require("transforms")
local text = require("text")

local dirsArg, ops = shell.parse(...)

if ops.help then
  print([[Usage: ls [OPTION]... [FILE]...
  -a, --all                  do not ignore entries starting with .
      --full-time            with -l, print time in full iso format
  -h, --human-readable       with -l and/or -s, print human readable sizes
      --si                   likewise, but use powers of 1000 not 1024
  -l                         use a long listing format
  -r, --reverse              reverse order while sorting
  -R, --recursive            list subdirectories recursively
  -S                         sort by file size
  -t                         sort by modification time, newest first
  -X                         sort alphabetically by entry extension
  -1                         list one file per line
  -p                         append / indicator to directories
  -M                         display Microsoft-style file and directory
                             count after listing
      --no-color             Do not colorize the output (default colorized)
      --help                 display this help and exit
For more info run: man ls]])
  return 0
end

if #dirsArg == 0 then
  table.insert(dirsArg, ".")
end

local ec = 0
local fOut = tty.isAvailable() and io.output().tty
local function perr(msg) io.stderr:write(msg,"\n") ec = 2 end
local set_color = function() end
local function colorize() return end
if fOut and not ops["no-color"] then
  local LSC = tx.foreach(text.split(os.getenv("LS_COLORS") or "", {":"}, true), function(e)
    local parts = text.split(e, {"="}, true)
    return parts[2], parts[1]
  end)
  colorize = function(info)
    return
      info.isLink and LSC.ln or
      info.isDir and LSC.di or
      LSC['*'..info.ext] or
      LSC.fi
  end
  set_color=function(c)
    io.write(string.char(0x1b), "[", c or "", "m")
  end
end
local msft={reports=0,proxies={}}
function msft.report(files, dirs, used, proxy)
  local free = proxy.spaceTotal() - proxy.spaceUsed()
  set_color()
  local pattern = "%5i File(s) %s bytes\n%5i Dir(s)  %11s bytes free\n"
  io.write(string.format(pattern, files, tostring(used), dirs, tostring(free)))
end
function msft.tail(names)
  local fsproxy = fs.get(names.path)
  if not fsproxy then
    return
  end
  local totalSize, totalFiles, totalDirs = 0, 0, 0
  for i=1,#names do
    local info = names[i]
    if info.isDir then
      totalDirs = totalDirs + 1
    else
      totalFiles = totalFiles + 1
    end
    totalSize = totalSize + info.size
  end
  msft.report(totalFiles, totalDirs, totalSize, fsproxy)
  local ps = msft.proxies
  ps[fsproxy] = ps[fsproxy] or {files=0,dirs=0,used=0}
  local p = ps[fsproxy]
  p.files = p.files + totalFiles
  p.dirs = p.dirs + totalDirs
  p.used = p.used + totalSize
  msft.reports = msft.reports + 1
end
function msft.final()
  if msft.reports < 2 then return end
  local groups = {}
  for proxy,report in pairs(msft.proxies) do
    table.insert(groups, {proxy=proxy,report=report})
  end
  set_color()
  print("Total Files Listed:")
  for _,pair in ipairs(groups) do
    local proxy, report = pair.proxy, pair.report
    if #groups>1 then
      print("As pertaining to: "..proxy.address)
    end
    msft.report(report.files, report.dirs, report.used, proxy)
  end
end

if not ops.M then
  msft.tail=function()end
  msft.final=function()end
end

local function nod(n)
  return n and (tostring(n):gsub("(%.[0-9]+)0+$","%1")) or "0"
end

local function formatSize(size)
  if not ops.h and not ops['human-readable'] and not ops.si then
    return tostring(size)
  end
  local sizes = {"", "K", "M", "G"}
  local unit = 1
  local power = ops.si and 1000 or 1024
  while size > power and unit < #sizes do
    unit = unit + 1
    size = size / power
  end
  return nod(math.floor(size*10)/10)..sizes[unit]
end

local function pad(txt)
  txt = tostring(txt)
  return #txt >= 2 and txt or "0"..txt
end

local function formatD