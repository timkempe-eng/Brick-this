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
source = open(path, encoding="utf-8").read()
lines = source.split("\n")


def code_only(line):
    """The part of `line` outside a comment, or "" if there is none.

    Handles `//` and `///` at the start, a trailing `//` after code, and `/* */`
    blocks. Not a Swift parser: a `//` inside a string literal is treated as the
    start of a comment, which errs toward refusing to mutate. That is the right
    direction — a refusal is visible and a mutation in the wrong place is not.
    """
    stripped = line.lstrip()
    if stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("/*"):
        return ""
    head = line.split("//", 1)[0]
    return head.split("/*", 1)[0]


def is_comment(line):
    return not code_only(line).strip()


if "\n" in old:
    # A multi-line target, matched against the file but judged by WHERE IT
    # LANDS rather than by what it says.
    #
    # The first attempt decided by inspecting the lines of `old`, then replaced
    # the first occurrence anywhere in the file — so a target whose first line
    # was code still landed happily inside a doc comment or a `"""…"""` sample
    # that happened to quote it. Judging the destination is the whole point.
    start = 0
    while True:
        at_char = source.find(old, start)
        if at_char < 0:
            sys.exit(1)
        first = source[:at_char].count("\n")
        span = lines[first:first + old.count("\n") + 1]
        if any(not is_comment(l) and l.strip() for l in span):
            break
        start = at_char + 1
    open(path, "w", encoding="utf-8").write(source[:at_char] + new + source[at_char + len(old):])
    print(first + 1)
    sys.exit(0)

for index, line in enumerate(lines):
    # The target must appear in the CODE part of the line, not merely somewhere
    # in it. A trailing `// … guard start >= horizon …` would otherwise be
    # mutated in place, which is the whole failure this file exists to stop.
    if old not in code_only(line):
        continue
    head = code_only(line)
    lines[index] = head.replace(old, new, 1) + line[len(head):]
    open(path, "w", encoding="utf-8").write("\n".join(lines))
    print(index + 1)
    sys.exit(0)

sys.exit(1)
