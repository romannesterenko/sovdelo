#!/usr/bin/env python3
import pathlib,sys
limit=64*1024*1024
with pathlib.Path(sys.argv[1]).open('wb') as out:
 total=0
 while chunk:=sys.stdin.buffer.read(1024*1024):
  total+=len(chunk)
  if total>limit:raise SystemExit('Release exceeds 64 MiB')
  out.write(chunk)
 if not total:raise SystemExit('Empty release')
