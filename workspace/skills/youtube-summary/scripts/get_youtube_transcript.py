#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path
from xml.etree import ElementTree as ET


def extract_video_id(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    if parsed.netloc in {'youtu.be', 'www.youtu.be'}:
        return parsed.path.strip('/').split('/')[0]
    if 'youtube.com' in parsed.netloc:
        qs = urllib.parse.parse_qs(parsed.query)
        if 'v' in qs:
            return qs['v'][0]
        parts = [p for p in parsed.path.split('/') if p]
        if len(parts) >= 2 and parts[0] in {'shorts', 'embed', 'live'}:
            return parts[1]
    raise SystemExit('Could not extract YouTube video id')


def fetch_text(url: str) -> str:
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode('utf-8', 'ignore')


def find_caption_tracks(html: str) -> list[dict]:
    marker = '"playerCaptionsTracklistRenderer":'
    idx = html.find(marker)
    if idx == -1:
        return []
    start = idx + len(marker)
    depth = 0
    in_str = False
    esc = False
    end = None
    for i, ch in enumerate(html[start:], start=start):
        if in_str:
            if esc:
                esc = False
            elif ch == '\\':
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        return []
    raw = html[start:end]
    data = json.loads(raw)
    return data.get('captionTracks') or []


def parse_transcript_payload(text: str) -> str:
    text = text.strip()
    if not text:
        return ''

    if text.startswith('{'):
        data = json.loads(text)
        parts = []
        for event in data.get('events', []):
            segs = event.get('segs') or []
            chunk = ''.join(seg.get('utf8', '') for seg in segs).replace('\n', ' ').strip()
            if chunk:
                parts.append(chunk)
        return re.sub(r'\s+', ' ', ' '.join(parts)).strip()

    root = ET.fromstring(text)
    parts = []
    for node in root.findall('.//text'):
        chunk = ''.join(node.itertext()).replace('\n', ' ').strip()
        if chunk:
            parts.append(chunk)
    return re.sub(r'\s+', ' ', ' '.join(parts)).strip()


def transcript_via_ytdlp(url: str) -> str:
    ytdlp = shutil.which('yt-dlp') or str(Path.home() / '.local' / 'bin' / 'yt-dlp')
    with tempfile.TemporaryDirectory() as tmp:
        outtmpl = str(Path(tmp) / 'cap')
        cmd = [
            ytdlp,
            '--skip-download',
            '--write-auto-subs',
            '--write-subs',
            '--sub-langs', 'ru.*,en.*,live_chat',
            '--sub-format', 'json3/vtt/best',
            '-o', outtmpl,
            url,
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        if proc.returncode != 0:
            return ''
        files = sorted(Path(tmp).glob('cap*.json3')) + sorted(Path(tmp).glob('cap*.vtt')) + sorted(Path(tmp).glob('cap*'))
        for p in files:
            try:
                text = p.read_text(encoding='utf-8', errors='ignore')
            except Exception:
                continue
            if p.suffix == '.json3':
                parsed = parse_transcript_payload(text)
            elif p.suffix == '.vtt':
                parsed = parse_vtt(text)
            else:
                parsed = parse_transcript_payload(text)
            if parsed:
                return parsed
    return ''


def parse_vtt(text: str) -> str:
    parts = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line == 'WEBVTT' or '-->' in line or line.isdigit():
            continue
        parts.append(line)
    return re.sub(r'\s+', ' ', ' '.join(parts)).strip()


def main() -> int:
    if len(sys.argv) < 2:
        print('Usage: get_youtube_transcript.py <youtube-url>', file=sys.stderr)
        return 2
    url = sys.argv[1].strip()
    video_id = extract_video_id(url)
    transcript = transcript_via_ytdlp(url)
    picked_lang = 'yt-dlp'
    if transcript:
        print(json.dumps({'ok': True, 'video_id': video_id, 'language': picked_lang, 'transcript': transcript}, ensure_ascii=False))
        return 0

    html = fetch_text(f'https://www.youtube.com/watch?v={video_id}')
    tracks = find_caption_tracks(html)
    if not tracks:
        print(json.dumps({'ok': False, 'error': 'No caption track found', 'video_id': video_id}, ensure_ascii=False, indent=2))
        return 1

    preferred_tracks = sorted(
        tracks,
        key=lambda tr: (0 if (tr.get('languageCode') or '').lower().startswith('ru') else 1,
                        0 if tr.get('kind') != 'asr' else 1)
    )

    transcript = ''
    picked_lang = None
    for tr in preferred_tracks:
        base_url = tr.get('baseUrl')
        if not base_url:
            continue
        sep = '&' if '?' in base_url else '?'
        try:
            payload_text = fetch_text(base_url + f'{sep}fmt=json3')
            transcript = parse_transcript_payload(payload_text)
        except Exception:
            transcript = ''
        if transcript:
            picked_lang = tr.get('languageCode')
            break

    if not transcript:
        print(json.dumps({'ok': False, 'error': 'Empty transcript', 'video_id': video_id}, ensure_ascii=False, indent=2))
        return 1
    print(json.dumps({'ok': True, 'video_id': video_id, 'language': picked_lang, 'transcript': transcript}, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
