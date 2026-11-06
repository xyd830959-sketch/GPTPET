# Playback runtime

FFmpeg is supplied separately and is not included in this source checkout.
Use an FFmpeg executable supporting libvpx-vp9 and WebM alpha, and pass its path
to `Start-FoxPet.ps1 -FfmpegPath ...`. No video generation model is needed.

The locally validated executable was FFmpeg 7.1 from imageio-ffmpeg 0.7.0,
with GPLv3-or-later build options. Its provider is https://www.gyan.dev/ffmpeg/builds/
and its source release is https://ffmpeg.org/releases/ffmpeg-7.1.tar.xz.
Obtain the executable from a source you trust and review that build's license.
This repository does not download or execute a new binary automatically.
