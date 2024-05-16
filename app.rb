#!/usr/bin/env ruby -I ../lib -I lib
# frozen_string_literal: true

require "sinatra/base"
require "sinatra/reloader"
require "openai"
require "byebug"

class App < Sinatra::Base
  configure :development do
    register Sinatra::Reloader
  end

  def self.beat_count
    2
  end

  def self.open_ai
    @open_ai ||= OpenAI::Client.new(
      access_token:ENV["OPENAI_API_KEY"],
      log_errors: true
    )
  end

  get '/' do
    "<form action='/' method='post' \
      enctype='multipart/form-data'>" \
      "<p>Upload file (must be 25mb or less)</p>" \
      "<input type='file' name='audio' accept='.mp3,audio/*' />" \
      "<br><input type='submit' value='Upload Audio' />" \
    "</form>"
  end

  post '/' do
    begin
      # Step 1: Convert the audio to text
      #step1_response = App.open_ai.audio.translate(
      #  parameters: {
      #    model: "whisper-1",
      #    file: File.open(params["audio"]["tempfile"], "rb"),
      #  }
      #)
      #transcription = step1_response["text"]
      transcription = "Our story begins in a town, more of a city really, but not as grand as Notting Spire itself. But Dumplecrag is the town, managed mostly by Baroness Rowena Goldcrest, and it's a bit north, about a day's march from Notting Spire. It's the tale of the Brief Orc War. It starts at a tavern called the Barking Squirrel, a fairly famous tavern for the people of Dumplecrag, as it's nestled in the base of a very large tree that has passed away before even Dumplecrag was founded. Of note in the establishment that night, among the crowd of people, was one wizard by the name of Quaz Squalzinger. He was a well-known wizard. He was a wizard that lots of people knew, but he wasn't the kind of wizard that people looked up to, right? I mean, he's hanging out at the Barking Squirrel tavern rather than at one of the non-drinking establishments that a wizard should probably spend more time. Well, he was there on this day, just enjoying some squire's stout. The establishment was visited by a whole platoon of the Dumplecrag guard. The captain of this militia could be heard commanding the bar patrons, and especially the bar owner, to hand over all of the stout. It had been ordered by Baroness Rowena Goldcrest that there was now a prohibition on drinking for all citizens within the realm governed by Dumplecrag. Quaz was not finishing his drink by any pace, was still leisurely enjoying it, sat there drinking quietly, watching cask after cask roll out of the Barking Squirrel. This other fellow is recognizable by some, a large head of brown curly hair, and is matched by a large curly beard. Not normal for a dwarf to have such curly hair, but that's the way that this Mark character really had it going for him. Quaz and Mark decided it was a good idea to go and find more ale, ale from a well-known alchemist, Serial Swirl of Siltmirth. Now, if you don't know, he is an alchemist who travels in a caravan. Now, they don't do anything evil, but they do what they want. Quaz, having a long friendship with Swirl, knew that it was the right place to go and also knew how to find him. Mark, on the other hand, didn't have much to contribute, but was willing to go along, maybe carry some stuff. With his mind made up, Quaz, Squall, Zinger, and Mark headed out to the Knotwood Forest. It is a forest, and it is made of trees, but it's confusingly named Knotwood. Stay with me. Quaz brought with him his horse by the name of Copper, not a very talkative horse, but he knows the roads and he's good with a map. It is evening time, they left shortly after their last drink at the Barking Squirrel. The forest is still fairly well lit from the moon and the beautiful starlight. So, feeling confident with this, they headed off. The peculiar thing this very night, though, was a bit of extra cloud. Now, it's not normally very cloudy in Dumblecrag, or much of all of Knot expire, and the day was a bit darker than it should be. Another curious thing, as it seemed that they were getting deeper into the forest, started to hear more crow noises. Crows, you know, a rare occurrence in Knotwood Forest. It seemed at this point their migratory patterns must have been bringing them in large amounts. Without much happening, they made it into a clearing, where they were expecting, as predicted by the artifact that Quaz was carrying, they did manage to find remnants of Swirl's caravan, knowing that he was probably just up the road having broken camp, most often moving at night time and brewing during the day. They did manage to chase him down, six to eight caravan carts going along, and somewhere near the middle was, of course, Swirl doing his usual antics of studying and tasting different ingredients and filling some of the more powder-based orders that he's got to do before he needs to set up again the next morning, and caught up with him and filled him in on what had just happened back at the Barking Squirrel, with the guards showing up and this strange decision by Baroness Rowena Goldcrest to start the Prohibition. Serial of Siltamereth seemed to know of this. Not necessarily the Prohibition starting, but that it was going to. As he had been told by some other travellers, orcish travellers in fact, as they had stopped by, happening upon Swirl's caravan, they were responding to, well, a requisition for payment to any and all able-bodied mercenaries out of the orcish colonies. What really stood out to Quaz, and Swirl as well, was that Baroness Rowena needed any sort of mercenaries. There was no expected threats. The last dragon had been chased out several years before. King Aldric Durnhelm had made it very clear that he was not going to tolerate that kind of stuff, so with their thoughts put together, ignoring Mark's contributions, they managed to decipher that it made the most sense that she was positioning for some sort of an invasion. While they were having this discussion, the air started to feel a little more alive, if you will. With a very easy magic cast, Quaz Squallzinger was able to detect that there was some magic up in the clouds. Not wanting to alarm anyone, he merely went and untethered copper and signalled for Mark to follow, thanking Serial for his time and paying him adequately for his knowledge. And of course, sharing one good brew together, which took a bit longer than it should have. Regretfully, it was during this respite, this extra ale that maybe neither of them needed, judging by the size of their stomachs, it was during this that the air did begin to actually be alive. There was no wind, there was no rain. It was merely lightning strikes, very rhythmic and very quickly. They moved, purposefully it felt like, through all eight of the carts, one after another. This was very powerful magic that summoned a storm to damage or deter this caravan. Well, in fact, it did destroy it, as the caravans began catching on fire. Quaz had already started off down the path a little bit into the forest, but by the time it hit the fifth caravan, the lightning strike cut down through the canopy, past the amount of crows that were sitting there, and striking instantaneously into the cart. Well, this was the gunpowder cart. The fire spread very quickly. The explosion knocked several of the large trees out of the way. With the roar of fire and trees chasing behind them, Quaz, Squalzinger, and Mark, and Copper, of course, carrying Quaz and all the stuff that Mark could no longer handle carrying, took off through the forest at a very, very quick pace. It was not just the lightning storm that was after them. For someone, somewhere in all of Notting Spire, was aware this information had been exchanged. Crows became the tool of whoever was puppeteering the magic. For the crows began to attack, first flying low and trying to scare Copper, the horse away from the path intended, began dropping lower and lower, their calls ringing through the forest, now very alive with shouts and screams and distant explosions of leftover alchemy materials. As Quaz began realizing the hostility of these crows, and Mark drawing his pitifully sharpened dagger, they prepared to defend themselves from these crows. The first wound that either of them sustained was a crow getting too close to Quaz and tearing at his shoulder, just a little bit, with one of its talons, but enough to put Quaz off and make him realize they needed to escape even faster. He led them down towards a river, where he happened to know a small supply cache was waiting for refugees of bandits, mostly. And he began telling Copper of the route that Copper should take. So down they rode into this ravine, and they did find the cache, a storage supply, a good place to release Copper and take all of Quaz's various weaponry and accoutrements and whatnot that he could handle, and abandon most of Mark's stuff that was of very little value and easily replaceable. The important part was there was a boat. Into it they go, Mark pushing off the boat for them and sloppily getting into the boat, Quaz having to use some magic to stabilize it, but they both made it, despite the persistent attacks. Mark's forearms becoming more and more bloodied as his rather large hair became a tangling net for a crow. On a low dive, getting the crow right in its brown curly locks, firmly tangled in his hair. Not much they could do about it, and they set course in pursuit of this murder of crows, ranging in the at least several hundred crows now, blocking out the starlight. Quaz having just enough glow on his protective barrier that they could tell where the boat was sailing. Now with the urgency of their journey and the mission now to deliver this message, and with the darkness, they punched their way out of the forest and into the opening field barrier between the two. Not inspired proper, they decided to head straight for the gate, knowing that they could get through it with help of the guards on the other side. Quaz being recognizable enough and Mark being loud enough with his crow fro, the gate opened and as they passed, they were joined by an escort, and quickly pulled to shore in order to get about their business. Now at this point, Mark, with his screaming crow stuck in his fro, was dismissed. Just left to wander in the streets. This is as much as we know about Mark. Quaz, Squallzinger, and several of his guard escorts headed straight for the castle. King Durnhelm sent a courier to Baroness Rowena and summoned me and the troops. Gathering in the great courtyard outside of the great hall, under the great balcony of the great kings. They are all truly great. Out in the great courtyard, it was there that the troops and I gave our speeches and drew up our battle plans, that it was indeed known now that Baroness Rowena was to march on Notting Spire. Her understanding of orcish war and their methods and abilities, she naively thought they would overpower us. Now I wish that I had the opportunity to tell you of the battle that was the brief orc war, for it lasted two full days. But I'm not able to tell you of that. For as we were preparing to leave, my dear friend Tannilin was marching in the gates, and spotting me and having no respect for the formalities of war and formations and marching orders and abusing the relationship of our friendship, he thought it would be of good importance to try and mount my horse with me to tell me of what he had been doing out in the forest. Well, Tannilin and my horse, they still don't get along. And upon seeing Tannilin, my horse pulled away, and Tannilin thought pulling the reins would be a good idea to help him climb up. And that's all I can remember. It was two days later when I woke up. Tannilin was sitting there by my bedside, happily informing me that, well, that I had a concussion, that, of course, none of his provocation, and me landing upon my head, ungracefully, in front of all of my troops. I am happy to say I do know that the orc war was brief, my army performed as it was supposed to, and that Tannilin had a wonderful time drinking my refreshments, flirting with my caregivers, and I quite suspect that his tea had mushrooms in it, as he couldn't stop telling me about them, and his eyes were about as dilated as I have ever seen them. And that, my friends, is what I know of the brief orcish war. Months later, on the very spot where Swirl's caravan, and Swirl himself, passed away, they would go back, name the newly-made clearing Knot Knotwood."
      puts "\n\nTranscription Complete:\n"
      puts transcription
      puts "\n\n"

      # Step 2: Convert the text to beats
      step2_response = App.open_ai.chat(
        parameters: {
          model: "gpt-4o",
          # model: "gpt-3.5-turbo", # good enough?
          response_format: { type: "json_object" },
          messages: [{
            role: "user",
            content: "Please consider the full text and extract 40, stand-alone bullet points from the following... resulting in a JSON array of strings:\n#{transcription}."
          }],
          temperature: 0.7,
        }
      )

      content =
        step2_response["choices"].first["message"]["content"]

      beats = JSON.parse(content)["bullet_points"]

      puts "\n\nBullet Point Extraction Complete:\n"
      beats.map{|b| puts b }
      puts "\n\n"

      byebug
    rescue StandardError => e
      byebug
    end
    puts ''
  end

  run!
end
