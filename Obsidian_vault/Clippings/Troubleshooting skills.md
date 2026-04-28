---
title: "Troubleshooting skills"
source: "https://www.youtube.com/watch?v=YBa1cwaG7is&list=PLmWCw1CzcFim_hkruZSlABOUOAAQ5JMyo&index=2"
author:
  - "[[Claude]]"
published: 2026-02-19
created: 2026-04-27
description: "When skills don't work, the problem usually falls into one of a few categories: the skill doesn't trigger, doesn't load, has conflicts, or fails at runtime. The good news is that most fixes are pretty"
tags:
  - "clippings"
---
![](https://www.youtube.com/watch?v=YBa1cwaG7is)

When skills don't work, the problem usually falls into one of a few categories: the skill doesn't trigger, doesn't load, has conflicts, or fails at runtime. The good news is that most fixes are pretty straightforward. Browse all courses and learn more: claude.com/resources/courses

## Transcript

**0:03** · When skills don't work, the problem usually falls into one of a few categories.

**0:09** · The skill doesn't trigger, doesn't load, has conflicts, or fails at runtime. But \[music\] good news, most fixes are pretty straightforward. Here are some of them.

**0:22** · First thing we can do is try the agent skills verifier command. Depending on your operating system, installation steps will differ, but we recommend using UV as it's the easiest way to get it installed fast. Once installed, either navigate to your skill directory or run this command from anywhere.

**0:41** · Your skill exists, it passes the validator, but Claude isn't using it when expected. H well, the cause is almost always the description. Cloud uses semantic matching, so your request needs to overlap with the description's meaning. If there's not enough overlap, no match. Check your description against how you're phrasing requests. Add trigger phrases users would actually say, test with variations. Help me profile this. Why is this slow? Make this faster.

**1:12** · If any fail to trigger, add those keywords to your description. If your skill doesn't appear when you ask Claude what skills are available, well, check these things. Skills must be in the right location with the right structure. The skill.md file must be inside of a name directory, not at a skills root. The file name must be exactly skill.md.

**1:34** · All caps on the skill lowerase MD. Just crossing things off the list here. Okay, just crossing them off. Run claude-debug to see loading errors. Look for messages mentioning your skill name. Sometimes this will just solve the problem for you. If Claude uses the wrong skill or seems confused, your descriptions are probably too similar. Make them distinct.

**1:57** · Remember, being as specific as possible doesn't just help with Claude deciding when to use your skill, but not conflicting with other similar sounding skills.

**2:07** · If your personal skill is being ignored, an enterprise or higher priority skill might have the same name. So investigate that. If you see an enterprise code review and you also have a personal code review, well the enterprise one will win every time. So your solutions is to rename your skill to something a little bit more distinct. Talk to your admin about the enterprise skill, but you'll have a better chance with number one.

**2:33** · Probably install the plugin but can't see it.

**2:37** · Skills? Well, clear the cache. Restart claw code and reinstall. If skills still don't appear, the plug-in structure just might be wrong. This is when the validator tool makes sense.

**2:49** · The skill loads but fails during execution. If your skill uses external packages, they must be installed. Add this info to your description.

**2:58** · Scripts need execute permission. Use for slashes everywhere, even on Windows.

**3:06** · So, here's a quick checklist. Not triggering? Well, improve your description and trigger phrases. Not loading? Check your path, file name, YAML syntax. Wrong skill \[music\] used?

**3:17** · Make your descriptions a little bit more distinct. Are you being shadowed? Check the priority and rename if needed.

**3:24** · Plugins are missing. Clear your cache and reinstall. Runtime failure? Check dependencies, permissions, and pass.