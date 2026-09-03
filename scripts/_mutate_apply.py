"""Apply one mutation to a code line, and print the line number.

Split out of `mutate.sh` so the shell does not have to nest a heredoc inside a
heredoc — which is how the previous attempt at this silently produced a broken
script.

Prints nothing and exits non-zero when the text appears only in comments, which
the caller reports as NOT APPLIED. That is the point: a mutation that lands in
a comment changes no behaviour, and a passing suite then reads as coverage that
does not exist.
"""
import sys

path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
source = open(path).read()
lines = source.split("\n")


def is_comment(line):
    return line.lstrip().startswith("//")


if "\n" in old:
    # A multi-line target is matched against the whole file. Refuse when every
    # line it would touch is a comment, which is the case this guards.
    if old not in source:
        sys.exit(1)
    at = source[:source.index(old)].count("\n") + 1
    if all(is_comment(l) or not l.strip() for l in old.split("\n")):
        sys.exit(1)
    open(path, "w").write(source.replace(old, new, 1))
    print(at)
    sys.exit(0)

for index, line in enumerate(lines):
    if is_comment(line) or old not in line:
        continue
    lines[index] = line.replace(old, new, 1)
    open(path, "w").write("\n".join(lines))
    print(index + 1)
    sys.exit(0)

sys.exit(1)
