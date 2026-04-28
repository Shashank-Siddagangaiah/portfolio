---
title: "Creating your first skill"
source: "https://www.youtube.com/watch?v=Wx6_vjFFyHM&list=PLmWCw1CzcFim_hkruZSlABOUOAAQ5JMyo&index=6"
author:
  - "[[Claude]]"
published: 2026-02-19
created: 2026-04-27
description: "Build a personal skill that teaches Claude how to write PR descriptions in a consistent format and learn how they work. Browse all courses and learn more: cl..."
tags:
  - "clippings"
---
![](https://www.youtube.com/watch?v=Wx6_vjFFyHM)

## Transcript

**0:03** · So, let's create a skill. This skill will teach Claude how we would like it to explain code using visual diagrams and analogies. \[music\] Then, we'll look at what happens under the hood when Claude uses it.

**0:18** · First, \[music\] let's create a directory for your skill. We're going to be making a personal skill, so it'll live in many projects, so it will go in your home directory. Take into consideration that we're creating a directory with the skill name inside of the skills directory.

**0:33** · Now create the skill.

**0:38** · The name identifies your skill. The description tells Claude when to use it.

**0:43** · This is the matching criteria. And then everything after the second dashes is the instructions that Claude follows.

**0:52** · Cloud code loads skills at startup. So restart your session. Then verify it's available.

**1:00** · You should see PR description in the list.

**1:04** · Now test it. Make some changes on a branch and say, "Write a PR description for my changes."

**1:11** · Claude will then show you that it's using the PR description skill.

**1:17** · After that, it'll check your diff and write a description following your template. Same format every single time.

**1:24** · When Cloud Code starts, it scans four locations for skills. Enterprise paths, your personal Claude skills, the project's Claude skills, and installed plugins. It loads only the name and description of each skill, not the full content. This is important later. When you send a request, Claude compares it to the descriptions of your skills.

**1:43** · Explain what this function does matches a skill described as explain code with visual diagrams because the intent overlaps. It will then ask you to confirm loading up the skill. This confirmation step keeps you aware of what context Claude is using. After you confirm, Claude reads the complete file and follows its instructions. Now, let's say you clone a Git repository and have an overlapping skill name. Well, which one wins? Here's the priority list. The highest is enterprise, which lives in the manage settings.

**2:13** · Two is the personal, which lives in your root directory configuration like we're doing right now. Three is the project which is the claw directory inside of your repository. And the lowest is the plugins where you store your plugins that you got online. This lets organizations enforce standards while allowing individual customization through differently named skills. If your company has an enterprise code review skill and you create a personal code review skill, the enterprise version of that takes precedence. To avoid conflicts, use descriptive names.

**2:47** · Instead of review, use front-end PR review or security review. To update a skill, edit it skill.md file. Simple. To remove one, delete its directory.

**3:00** · Restart clock code after changes for them to take effect.

**3:06** · Creating a skill means making a directory with a skill.md file containing metadata and instructions.

**3:13** · Claude loads skill names and descriptions at startup. matches incoming requests against those descriptions and asks for confirmation before loading the full content.

**3:25** · Priority rules handling name conflicts.

**3:27** · Enterprise overrides personal personal overrides project overrides plugins.

**3:32** · \[music\] Edit the skill.md file to update a skill and restart cloud code for changes to take effect.