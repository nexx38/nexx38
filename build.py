#!/usr/bin/env python3
"""Bundle index.html + all CSS/JS into a single self-contained app.html.

If vendor/chart.min.js exists (downloaded by CI), Chart.js is inlined → fully offline.
Otherwise falls back to the CDN (requires internet on first load).
"""
import re, sys, os, urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))

CSS_FILES = ['css/styles.css', 'css/scanner.css', 'css/modules.css']
JS_FILES = ['js/data.js', 'js/calc.js', 'js/scanner.js', 'js/product_data.js',
            'js/modules.js', 'js/modules_ui.js', 'js/app.js']

CHART_CDN  = 'https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js'
CHART_FILE = os.path.join(ROOT, 'vendor', 'chart.min.js')

# Try to download Chart.js if not cached locally
if not os.path.exists(CHART_FILE):
    os.makedirs(os.path.join(ROOT, 'vendor'), exist_ok=True)
    try:
        print('Downloading Chart.js …')
        urllib.request.urlretrieve(CHART_CDN, CHART_FILE)
        print('Chart.js downloaded.')
    except Exception as e:
        print(f'Chart.js download failed ({e}) — will use CDN reference.')
        if os.path.exists(CHART_FILE):
            os.remove(CHART_FILE)

css = '\n'.join(open(os.path.join(ROOT, f), encoding='utf-8').read() for f in CSS_FILES)
js  = '\n'.join(open(os.path.join(ROOT, f), encoding='utf-8').read() for f in JS_FILES)

html = open(os.path.join(ROOT, 'index.html'), encoding='utf-8').read()
html = re.sub(r'\s*<link rel="stylesheet" href="css/[^"]*">', '', html)
html = re.sub(r'\s*<script src="js/[^"]*"></script>', '', html)
html = re.sub(r'\s*<script src="https://cdn\.jsdelivr\.net[^"]*"></script>', '', html)

html = html.replace('</head>', f'<style>\n{css}\n</style>\n</head>', 1)

if os.path.exists(CHART_FILE):
    chart_js = open(CHART_FILE, encoding='utf-8').read()
    chart_tag = f'<script>\n{chart_js}\n</script>'
    print('Chart.js: inlined (fully offline)')
else:
    chart_tag = f'<script src="{CHART_CDN}"></script>'
    print('Chart.js: CDN reference (internet required for charts)')

html = html.replace('</body>', f'{chart_tag}\n<script>\n{js}\n</script>\n</body>', 1)

leftover = re.findall(r'<(?:script src|link rel="stylesheet" href)="(?:js|css)/[^"]*"', html)
if leftover:
    sys.exit(f'BUILD FAILED – leftover local references: {leftover}')

out = os.path.join(ROOT, 'app.html')
open(out, 'w', encoding='utf-8').write(html)
print(f'OK – app.html written ({len(html)//1024} KB)')
