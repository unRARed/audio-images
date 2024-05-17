Audio to Images
===============

This tool takes an MP3 as input via a web form and creates
a number of images based on the audio files contents in
a minimalist, black and white pencil drawing style.

Getting Started
---------------

- Ensure `OPENAI_API_KEY` is set to your particular API key
- Add the upscaler:
  `wget https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip`
  `unzip realesrgan-ncnn-vulkan-20220424-macos.zip`
  `chmod u+x realesrgan-ncnn-vulkan`
  `rm realesrgan-ncnn-vulkan-20220424-macos.zip`
- Run `ruby app.rb`
- Visit <http://127.0.0.1:4567> and upload your audio
