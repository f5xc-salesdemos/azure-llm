#!/bin/bash
# ==============================================================================
# SECTION 4: MEDIA & CONTENT PROCESSING
# ==============================================================================

apt-get install -y \
  ffmpeg poppler-utils qrencode \
  imagemagick exiv2 mediainfo graphviz

# Install yt-dlp (video/audio downloader)
curl -Lo /usr/local/bin/yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" && chmod +x /usr/local/bin/yt-dlp

echo "Media processing tools installed"
