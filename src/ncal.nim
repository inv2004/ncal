import times
import strutils
import strformat
import terminal
import sequtils
import os
import httpclient
import json

const APP = "ccal"
const ONE_DAY = initDuration(days = 1)
const HTTP_HEADERS = {"User-Agent": "curl/8.5.0"}
const HTTP_TIMEOUT = 200
const IP_INFO_URL = "https://ipinfo.io"
const HOLIDAYS_URL = "https://date.nager.at/api/v3/PublicHolidays"

proc nl() =
  stdout.writeLine ""

proc mons(mm: openArray[Month], year: int, today: DateTime, holidays: seq[string]) =
  var dts = mm.mapIt(dateTime(year, it, 1, 0, 0, 0))
  for i, dt in dts:
    if i > 0:
      stdout.write "   "
    if today.month == dt.month and today.year == dt.year:
      stdout.styledWrite(styleUnderscore, bgBlue, fmt"{dt.month:^20}")
    else:
      stdout.styledWrite(styleUnderscore, fmt"{dt.month:^20}")
  nl()

  for i, dt in dts:
    if i > 0:
      stdout.write "   "
    stdout.styledWrite(styleUnderscore, toSeq(dMon..dSun).mapIt(($it)[
        0..1]).join(" "))
  nl()

  for _ in 1..6:
    var i = 0
    for dt in dts.mitems:
      if i > 0:
        stdout.write "   "
      if dt.month != mm[i]:
        stdout.write(" ".repeat(max(0, 3*7 - 1)))
      else: 
        stdout.write(" ".repeat(max(0, 3*int(dt.weekday()) - 1)))
        while dt.month() == mm[i]:
          if dt.weekDay != dMon:
            stdout.write " "
          if dt.format("yyyy-MM-dd") in holidays:
            if today.monthday == dt.monthday and today.month == dt.month and today.year == dt.year:
              stdout.styledWrite(bgRed, fmt"{dt.monthday():2}")
            else:
              stdout.styledWrite(fgRed, fmt"{dt.monthday():2}")
          elif dt.weekDay in [dSun, dSat]:
            if today.monthday == dt.monthday and today.month == dt.month and today.year == dt.year:
              stdout.styledWrite(bgBlue, fmt"{dt.monthday():2}")
            else:
              stdout.styledWrite(fgBlue, fmt"{dt.monthday():2}")
          else:
            if today.monthday == dt.monthday and today.month == dt.month and today.year == dt.year:
              stdout.styledWrite(bgBlue, fmt"{dt.monthday():2}")
            else:
              stdout.write(fmt"{dt.monthday():2}")
          dt += ONE_DAY
          if dt.weekday == dMon:
            break
        if dt.month() != mm[i]:
          stdout.write(" ".repeat(3*(6 - int(weekday(dt - ONE_DAY)))))
      i.inc
    nl()

proc cacheHolidays(cacheDir: string, country: string, year: int): string =
  let client = newHttpClient(timeout = HTTP_TIMEOUT, headers = newHttpHeaders(HTTP_HEADERS))
  var c = country
  if country == "":
    result = client.getContent(IP_INFO_URL).parseJson()["country"].getStr().toLower()
  let buf = client.getContent(fmt"{HOLIDAYS_URL}/{year}/{result}")
  if not dirExists(cacheDir):
    createDir(cacheDir)
  if buf.parseJson().getElems().len == 0:
    return ""
  let file = cacheDir / fmt"{year}_{c}"
  writeFile(file, buf)
  if country == "":
    createSymlink(file, cacheDir / $year)

proc findHolidays(year: int, country: string): (string, seq[string]) =
  let cacheDir = getCacheDir(APP)
  var file = cacheDir / $year
  if country != "":
    file.add ("_" & country)
    result[0] = country
  if not fileExists(file):
    result[0] =
      try:
        cacheHolidays(cacheDir, country, year)
      except OSError:
        stderr.writeLine getCurrentExceptionMsg()
        return
    if result[0] == "":
      return  
  else:
    let parts = expandSymlink(file).extractFilename().split('_')
    doAssert parts.len == 2
    result[0] = parts[1]
  result[1] = readFile(file).parseJson().getElems().mapIt(it["date"].getStr())

proc printYear(year: int, country: string, today: DateTime) =
  let (country, holidays) = findHolidays(year, country)

  if year == today.year:
    stdout.styledWrite(bgBlue, $year)
  else:
    stdout.write $year
  stdout.write fmt" ({country})"
  nl()
  nl()

  for mm in distribute(toSeq(mJan..mDec), 3):
    mons(mm, year, today, holidays)

proc parseArgs(): (seq[int], string) =
  for i in 1..paramCount():
    if paramStr(i) in ["-h", "--help"]:
      echo fmt"{paramStr(0)} [year(s)] [country]"
      quit 0
    elif paramStr(i) in ["--clean"]:
      removeDir(getCacheDir(APP))
      quit 0
    try:
      let y = parseInt(paramStr(i))
      result[0].add (if y < 100: 2000+y else: y)
    except ValueError:
      result[1] = paramStr(i)

proc main() =
  let (years, country) = parseArgs()
  let today = now()
  if years.len == 0:
    printYear(today.year(), country, today)
  else:
    for i, y in years:
      if i > 0:
        nl()
      printYear(y, country, today)

when isMainModule:
  main()
