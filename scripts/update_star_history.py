#!/usr/bin/env python3
"""Record a daily UTC star-count observation and render README charts.

Run from a checkout with GitHub CLI authentication. Historical observations are
retained; no counts before the first observation are inferred.
"""
import json
import math
from datetime import date, datetime, timezone
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'docs' / 'media' / 'stars'
FONT = 'system-ui, -apple-system, BlinkMacSystemFont, &quot;Segoe UI&quot;, sans-serif'


def render(points, dark=False):
    foreground, muted, grid, accent, background = (
        ('#f0f6fc', '#9198a1', '#3d444d', '#4493f8', '#0d1117') if dark else
        ('#1f2328', '#59636e', '#d1d9e0', '#0969da', '#ffffff'))
    first, last = date.fromisoformat(points[0]['date']), date.fromisoformat(points[-1]['date'])
    span = max(1, (last - first).days)
    maximum = max(4, max(p['count'] for p in points))
    step = max(1, math.ceil(maximum / 4))
    ceiling = step * 4
    xy = [(64 + 624 * (date.fromisoformat(p['date']) - first).days / span,
           224 - 144 * p['count'] / ceiling) for p in points]
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="720" height="300" viewBox="0 0 720 300" role="img" aria-labelledby="title desc">',
             '<title id="title">iLibrary Star History</title>',
             f'<desc id="desc">Daily observations since {first}. Latest observation: {points[-1]["count"]} stars on {last} UTC. Unobserved dates are not reconstructed.</desc>',
             f'<style>text {{ font-family: {FONT}; fill: {muted}; font-size: 12px; }}</style>',
             f'<rect width="720" height="300" rx="8" fill="{background}"/>',
             f'<text x="32" y="36" style="fill:{foreground};font-size:18px;font-weight:600">Star History</text>',
             f'<text x="688" y="36" text-anchor="end">{points[-1]["count"]} stars</text>']
    for tick in range(5):
        y = 224 - tick * 36
        parts += [f'<path d="M64 {y} H688" stroke="{grid}" stroke-width="1"/>',
                  f'<text x="50" y="{y + 4}" text-anchor="end">{tick * step}</text>']
    if len(xy) > 1:
        parts.append(f'<polyline points="{" ".join(f"{x:.2f},{y:.2f}" for x, y in xy)}" fill="none" stroke="{accent}" stroke-width="2.5"/>')
    x, y = xy[-1]
    parts.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="4" fill="{accent}"/>')
    parts.append(f'<text x="64" y="248">{first}</text>')
    if first != last:
        parts.append(f'<text x="688" y="248" text-anchor="end">{last}</text>')
    parts.append('<text x="32" y="280">Daily observations · UTC · Lines connect recorded counts.</text>')
    return '\n'.join(parts + ['</svg>', ''])


def main():
    metadata = json.loads(subprocess.check_output(
        ['gh', 'api', 'repos/x96x64/ilibrary'], text=True))
    count = metadata['stargazers_count']
    if type(count) is not int or count < 0:
        raise ValueError('Invalid star count')
    output = OUTPUT / 'history.json'
    points = json.loads(output.read_text()) if output.exists() else []
    today = datetime.now(timezone.utc).date().isoformat()
    # A repeated run replaces the same day's observation, including decreases.
    observations = {p['date']: p['count'] for p in points}
    observations[today] = count
    points = [{'date': day, 'count': value} for day, value in sorted(observations.items())]
    for p in points:
        date.fromisoformat(p['date'])
        if type(p['count']) is not int or p['count'] < 0:
            raise ValueError('Invalid historical star count')
    charts = {f'{theme}.svg': render(points, theme == 'dark') for theme in ('light', 'dark')}
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, chart in charts.items():
        (OUTPUT / name).write_text(chart)
    output.write_text(json.dumps(points, indent=2) + '\n')


if __name__ == '__main__':
    main()
