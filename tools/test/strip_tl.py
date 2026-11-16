import re,sys
def strip(src):
    out=[]
    for line in src.splitlines():
        line=re.sub(r'\bug_require(\s*"[^"]*")\s+as\s+[\w.]+', r'require\1', line)
        line=re.sub(r'^(\s*local\s+\w+)\s*:\s*[^=]+?(\s*=)', r'\1\2', line)
        def params(m):
            ps=[re.sub(r'\s*:.*$','',p.strip()) for p in m.group(2).split(',')] if m.group(2).strip() else []
            return m.group(1)+'('+', '.join(ps)+')'
        line=re.sub(r'(\bfunction\s*[\w.:]*)\(([^()]*)\)(\s*:\s*[\w.<>{}, ]+?)?(\s*$)', lambda m: params(m)+m.group(4), line)
        line=re.sub(r'(\bfunction\s*[\w.:]*)\(([^()]*)\)\s*:\s*[\w.<>{}]+', lambda m: params(m), line)
        line=re.sub(r'\s+as\s+[\w.<>{}]+(?=[\s,)\]}]|$)', '', line)
        out.append(line.rstrip())
    return '\n'.join(out)+'\n'
sys.stdout.write(strip(open(sys.argv[1]).read()))
