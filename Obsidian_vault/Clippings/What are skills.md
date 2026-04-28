---
title: "What are skills?"
source: "https://www.youtube.com/watch?v=bjdBVZa66oU&list=PLmWCw1CzcFim_hkruZSlABOUOAAQ5JMyo&index=1"
author:
  - "[[Claude]]"
published: 2026-02-27
created: 2026-04-27
description: "A skill teaches Claude how to do something once. Then, Claude then applies that knowledge automatically whenever it's relevant. Browse all courses and learn more: claude.com/resources/courses"
tags:
  - "clippings"
---
![](https://www.youtube.com/watch?v=bjdBVZa66oU)

A skill teaches Claude how to do something once. Then, Claude then applies that knowledge automatically whenever it's relevant. Browse all courses and learn more: claude.com/resources/courses

## Transcript

**0:03** · Every time you explain your team's coding standards to Claude, you're repeating yourself.

**0:09** · Every PR review, you redescribe how you want feedback \[music\] structured. Every commit message, you remind Claude of your preferred format, and skills fix this. A skill is a markdown file that teaches Claude \[music\] how to do something once, and Claude applies that knowledge automatically whenever it's relevant.

**0:32** · Agent skills are folders of instructions, scripts, and resources that Asia can discover and use to do things more accurately and efficiently.

**0:41** · With Claw Code, we have the skill MD file. The description is how Claw decides whether to use the skill. When you ask Claude to review this PR, it matches your request against available skill descriptions and finds this one.

**0:57** · Claude reads your request, compares it to all available skill descriptions, and activates the ones that match.

**1:05** · You can store skills in a few places depending on who needs them. Personal skills go in the home directory.cloud/skills and follow you across all your project.

**1:17** · These are your preferences, your commit message style, your documentation format, how you like code explained.

**1:24** · Project skills go in the do.claw/skills inside of the root directory of your repository. Anyone who clones the repository gets these skills automatically. This is where team standards live, like your company's brand guidelines, preferred fonts, and colors that you use for web design.

**1:43** · Cloud code has several ways to customize behavior. Skills are unique because they're automatic and task specific.

**1:51** · CloudMD files load into every conversation. If you want claw to always use typescript strict mode that goes in your claw.md file. Skills on the other hand load on demand when they match your request. It only loads in the name and description. So it doesn't fill up your entire context window. Your PR review checklist doesn't need to be in the context when you're debugging. It loads when you actually ask for a review.

**2:17** · Slash commands require you to type them.

**2:19** · Skills don't. Claude applies them when it recognizes the situation.

**2:27** · Skills work best for specialized knowledge that applies to specific tasks, code review standards your team follows, commit message formats that you prefer, brand guidelines of your organization.

**2:42** · If you find yourself explaining the same thing \[music\] to Claude repeatedly, well, that's a skill waiting to be written.