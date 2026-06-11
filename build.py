#!/usr/bin/env python3
"""Bundle index.html + all CSS/JS into a single self-contained app.html."""
import re, sys, os

ROOT = os.path.dirname(os.path.abspath(__file__))

CSS_FILES = ['css/styles.css', 'css/scanner.css', 'css/modules.css']
JS_FILES = ['js/data.js', 'js/calc.js', 'js/scanner.js', 'js/product_data.js',
            'js/modules.js', 'js/modules_ui.js', 'js/app.js']

css = '\n'.join(open(os.path.join(ROOT, f), encoding='utf-8').read() for f in CSS_FILES)
js = '\n'.join(open(os.path.join(ROOT, f), encoding='utf-8').read() for f in JS_FILES)

html = open(os.path.join(ROOT, 'index.html'), encoding='utf-8').read()

html = re.sub(r'\s*<link rel="stylesheet" href="css/[^"]*">', '', html)
html = re.sub(r'\s*<script src="js/[^"]*"></script>', '', html)
html = re.sub(r'\s*<script src="https://cdn\.jsdelivr\.net[^"]*"></script>', '', html)

html = html.replace('</head>', f'<style>\n{css}\n</style>\n</head>', 1)
html = html.replace('</body>',
    '<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>\n'
    f'<script>\n{js}\n</script>\n</body>', 1)

# Sanity checks: no external local references may remain
leftover = re.findall(r'<(?:script src|link rel="stylesheet" href)="(?:js|css)/[^"]*"', html)
if leftover:
    sys.exit(f'BUILD FAILED – leftover local references: {leftover}')

out = os.path.join(ROOT, 'app.html')
open(out, 'w', encoding='utf-8').write(html)
print(f'OK – app.html written ({len(html)//1024} KB)')
