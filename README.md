Audio to Images
===============

This tool takes an MP3 as input via a web form and generates a
number of images via the Open AI API in this sequence:

- Audio File -> Transcription
- Transcription -> `n` Summarized Prompts
- Summarized Prompts -> Short Global Summary
- Indiviual Prompt + Global Summary -> Image

After generation is complete, and "Optimize" option will perform
a handful of `imagemagick` operations on the generated content.

### Setup

You'll need `ruby`, maybe `wget` and `imagemagick`.

- Run `bundle install`
- Ensure `OPENAI_API_KEY` is set to your particular API key
- Add the upscaler:
  `wget https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip`
  `unzip realesrgan-ncnn-vulkan-20220424-macos.zip`
  `chmod u+x realesrgan-ncnn-vulkan`
  `rm realesrgan-ncnn-vulkan-20220424-macos.zip`

### Up and Running

- Run `ruby app.rb` (or `DEBUG=1 ruby app.rb` for more logging)
- Visit <http://127.0.0.1:4567> and upload your audio

Example Output
--------------

Example projects are included from:

- [./projects/example_1](https://github.com/unRARed/audio-images/tree/main/projects/example_1)
- [./projects/example_2](https://github.com/unRARed/audio-images/tree/main/projects/example_2)

The first example was a music recording with only a style provided.
The second example was per the narration from
[this YouTube video](https://www.youtube.com/watch?v=2Azuja9Afyo)
having both a style and context. However, the additional context of
"There's always bats." was overlooked during the prompt generation.
Some fine tuning of the prompting is still needed.

### UI Example

![Project Example Output](https://raw.githubusercontent.com/unRARed/audio-images/main/project-example.jpg)
