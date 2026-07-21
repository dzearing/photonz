#!/usr/bin/env python3
"""VR6: delete the page-local rules that shared/photonz-ds.css now owns.

Only removes a rule when BOTH its selector and its whitespace-normalized body
match a promoted primitive EXACTLY, and only at the top level of the page's
<style> block. A rule nested in @media/@container is a responsive override with
a different meaning, and a rule whose body has drifted is a real divergence the
page still needs -- both are left alone and reported.

Run with --apply to write; default is a dry run.
"""
import re, os, sys

PROMOTED = [
    # (selector regex matched against the whole selector, normalized body)
    (r'^(#[\w-]+ )?\.win\.shell \.canvas$', 'min-height:0'),
    (r'^(#[\w-]+ )?\.pglead$', 'font-size:12.5px;color:var(--dim);line-height:1.5;margin:0 0 var(--gap)'),
    (r'^(#[\w-]+ )?\.pglead b$', 'color:var(--ink);font-weight:600'),
    (r'^(#[\w-]+ )?\.mlabel$', 'font-size:9px;letter-spacing:.08em;text-transform:uppercase;color:var(--faint);font-weight:700;padding:6px 10px 3px'),
    (r'^(#[\w-]+ )?\.(setrow|rrow) \.rl$', 'color:var(--faint);font-size:10.5px'),
    (r'^(#[\w-]+ )?\.setrow$', 'display:grid;grid-template-columns:1fr auto;align-items:center;gap:var(--s2);padding:4px 0'),
    (r'^(#[\w-]+ )?\.actstack$', 'display:flex;flex-direction:column;gap:var(--gap-sm);margin-top:var(--s1)'),
    (r'^(#[\w-]+ )?\.seg\.stack$', 'flex-wrap:wrap;width:100%'),
    (r'^(#[\w-]+ )?\.seg\.stack button$', 'flex:1 1 auto;white-space:nowrap'),
]

norm = lambda s: re.sub(r'\s+', '', s).rstrip(';')


def top_level_rules(css):
    """Yield (start, end, selector, body) for rules at nesting depth 0."""
    depth, i, n = 0, 0, len(css)
    sel_start = 0
    while i < n:
        c = css[i]
        if c == '/' and css[i:i+2] == '/*':
            j = css.find('*/', i)
            i = (j + 2) if j != -1 else n
            continue
        if c == '{':
            sel = css[sel_start:i]
            if depth == 0 and not sel.strip().startswith('@'):
                j, d2 = i + 1, 1
                while j < n and d2:
                    if css[j] == '{':
                        d2 += 1
                    elif css[j] == '}':
                        d2 -= 1
                    j += 1
                yield sel_start, j, sel.strip(), css[i+1:j-1]
                i, sel_start = j, j
                continue
            depth += 1
        elif c == '}':
            depth -= 1
            if depth <= 0:
                depth = 0
                sel_start = i + 1
        elif c == ';' and depth == 0:
            sel_start = i + 1
        i += 1


def main():
    apply = '--apply' in sys.argv
    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pages'))
    removed = kept = 0
    per_page, divergent = {}, []
    for fn in sorted(os.listdir('.')):
        if not fn.endswith('.html'):
            continue
        src = open(fn).read()
        style = re.search(r'(<style[^>]*>)(.*?)(</style>)', src, re.S)
        if not style:
            continue
        css = style.group(2)
        cuts = []
        for a, b, sel, body in top_level_rules(css):
            sel1 = ' '.join(sel.split())
            for pat, want in PROMOTED:
                if re.match(pat, sel1):
                    if norm(body) == norm(want):
                        cuts.append((a, b, sel1))
                    else:
                        divergent.append((fn, sel1, ' '.join(body.split())[:80]))
                    break
        if not cuts:
            continue
        out = css
        for a, b, sel1 in sorted(cuts, reverse=True):
            # swallow one trailing newline so deletions leave no blank gaps
            end = b + 1 if out[b:b+1] == '\n' else b
            out = out[:a] + out[end:]
        out = re.sub(r'\n{3,}', '\n\n', out)
        per_page[fn] = [s for _, _, s in cuts]
        removed += len(cuts)
        if apply:
            open(fn, 'w').write(src[:style.start(2)] + out + src[style.end(2):])
    print(('APPLIED' if apply else 'DRY RUN') + f': removed {removed} rules from {len(per_page)} pages')
    for fn, sels in sorted(per_page.items()):
        print(f'  {fn}: ' + ', '.join(sels))
    if divergent:
        print(f'\nLEFT ALONE ({len(divergent)} divergent bodies -- these pages really do differ):')
        for fn, sel, body in divergent:
            print(f'  {fn}: {sel} {{ {body} }}')


main()
