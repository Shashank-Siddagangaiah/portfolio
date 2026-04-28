---
title: "Configuration and multi-file skills"
source: "https://www.youtube.com/watch?v=98KaK_rn5rQ&list=PLmWCw1CzcFim_hkruZSlABOUOAAQ5JMyo&index=5"
author:
  - "[[Claude]]"
published: 2026-02-19
created: 2026-04-27
description: "A basic skill works with just a name and description, but there are several advanced techniques that can make your skills much more effective in Claude Code. Explore the key fields, best practices for"
tags:
  - "clippings"
---
![](https://www.youtube.com/watch?v=98KaK_rn5rQ)

A basic skill works with just a name and description, but there are several advanced techniques that can make your skills much more effective in Claude Code. Explore the key fields, best practices for descriptions, tool restrictions, and how to structure larger skills. Browse all courses and learn more: claude.com/resources/courses

## Transcript

**0:02** · A basic skill works with just a name and description, but here are some other advanced tips that can make your skills really effective in claw code.

**0:12** · The agentskills.io open standard has many available fields. We already went over the name, which identifies your skill, uses lowercase letters, numbers, and hyphens only. A maximum of 64 characters and should match your directory name. a description which is also required which tells Claude when to use the skill. This is a maximum of,024 characters and is the most important field. Claude uses this for matching.

**0:37** · But we can also add other optional fields. One of them is the allowed tools field which restricts which tools Claude can use when the skill is active. The model field which specifies which cla model to use for the skill. Try to be explicit with your instructions. For example, if someone told me my job was to help with dogs, I wouldn't know what to do. So, we have to assume Claude would think the same way. A good description answers two questions. What does this skill do? And when should Claus use it?

**1:08** · Now, if this job description was given to me, I feel a little bit more confident that I could get the job done.

**1:14** · If your skill isn't triggering, add more keywords that match how you phrase requests.

**1:20** · Sometimes you want a skill that can only read files, not modify them. This could be for security sensitive workflows, read only tasks or more. We have the allowed tools field to make this possible. When this skill is active, Claw can only use those tools without asking permission. No editing, no writing, no bash commands. If you omit allowed tools, the skill doesn't restrict anything. Claude uses its normal permission model.

**1:49** · Skills share Claw's context window with your conversation. When Claude wants to use a skill, it will decide to load the contents of that skill into context.

**1:58** · However, sometimes you'll need some references, examples, or some utility scripts that are required by the skill.

**2:06** · But cramming it all into one 20,000 line text file means you take up a lot of space in the context window. And let's be real here, it's just not a lot of fun to maintain that. This is where progressive disclosure comes in. Put your essential instructions in skill.mmp and detailed reference material in separate files that Claude reads only when needed. The open standard also suggests having a scripts folder for executable code, references for additional documentation and assets for images, templates or other data files that would be relevant for that skill.

**2:39** · Then in skill.md link to the supporting files. Here, Claude reads architecture.md only when someone asks about system design. If they're asking where to add a component, let's say, it just never loads. It's like having a table of contents in the context window rather than fitting the whole entire document in there. Keep skill.md under 500 lines. If you're exceeding that, then maybe consider should this be split up into different content.

**3:08** · Scripts in your skill directory can run without loading their contents into context. The script executes and only the output consumes tokens. Tell claw to run the script, not read it. This is very useful for environment validation, data transformations that need to be consistent, operations that are more reliable as tested code than generated code.

**3:31** · Skills support metadata fields. Name and description which are required. Allowed tools restricts available tools and model specifies which claw to use.

**3:40** · Descriptions need specific actions and trigger phrases to match for reliability. For larger skills, use progressive disclosure. Keep your skill.md file under 500 lines and link to the supporting files that load only when needed. Scripts \[music\] can execute without loading their contents, keeping context efficient.