---
name: youtube-summary
description: Summarize YouTube videos from a link using the local Summarizely + yt-dlp + Codex CLI pipeline without separate provider API keys. Use when the user sends a YouTube URL and wants a concise or detailed summary, key points, or the main idea of the video.
---

# YouTube Summary

Use this skill when the user sends a YouTube link and asks for a summary.

## Workflow

1. Run `scripts/youtube_summarize.sh "<youtube-url>"`.
2. If the Summarizely pipeline succeeds, use its generated markdown summary as the primary source.
3. If Summarizely fails, run `scripts/get_youtube_transcript.py "<youtube-url>"` as fallback.
4. If transcript extraction still fails, say clearly that subtitles were unavailable and offer a fallback based on title/description only.
5. For the default response, provide:
   - brief summary
   - main idea
   - 3-7 key points
6. If the user asks for more depth, also provide:
   - notable claims
   - practical takeaways
   - weak points / caveats

## Output style

Prefer:
- **Кратко:** 2-4 sentences
- **Суть:** 1-2 sentences
- **Ключевые мысли:** bullets

## Notes

- Primary path: `summarizely` + `yt-dlp` + `codex` CLI.
- Fallback path: transcript script using `yt-dlp` subtitles and YouTube page caption tracks.
- Do not pretend you watched the video if extraction failed.
- If auto-generated captions exist, mention that the summary is based on subtitles and may contain recognition errors.
- The wrapper binary used by this skill is `scripts/bin/codex`, which injects `--skip-git-repo-check` for `codex exec`.
