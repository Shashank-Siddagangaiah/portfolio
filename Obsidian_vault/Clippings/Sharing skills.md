---
title: "Sharing skills"
source: "https://www.youtube.com/watch?v=OCBi3eScNLk&list=PLmWCw1CzcFim_hkruZSlABOUOAAQ5JMyo&index=3"
author:
  - "[[Claude]]"
published: 2026-02-19
created: 2026-04-27
description: "Skills become much more valuable when they're shared. Explore the different ways you can distribute skills. Browse all courses and learn more: claude.com/resources/courses"
tags:
  - "clippings"
---
![](https://www.youtube.com/watch?v=OCBi3eScNLk)

Skills become much more valuable when they're shared. Explore the different ways you can distribute skills. Browse all courses and learn more: claude.com/resources/courses

## Transcript

**0:02** · Skills become more valuable when shared.

**0:05** · A PR review skill that only you use is helpful. The same skill shared across your team standardizes code review and provides a consistent experience amongst your organization which much better.

**0:16** · Here are ways you can share your skills.

**0:20** · Now the simplest sharing method is committing skills to your repository.

**0:24** · Place them include/skills.

**0:27** · Anyone who clones a repository gets these skills automatically. No extra installation. It's just what you're doing already. When you push update, everyone gets them on the next poll.

**0:38** · This works well for team coding standards, project specific workflows, skills that reference your codebase structure.

**0:47** · Another way you can distribute your skills is through plugins. Think of plugins as ways to extend cloud code with custom functionality, but designed to be shared across teams and projects.

**1:01** · In your plug-in project, create a directory called skills. This will then follow a similar file structure to the cloud directory in our project with the name of the skill with a skill.md file.

**1:13** · And after you distribute your plugin to a marketplace, other users can download it into cloud codes for themselves to use.

**1:20** · This is best if your skills have functionality that isn't too project specific and can be used by community members.

**1:30** · Administrators can deploy skills organizationwide through managed settings. Enterprise skills take highest priority. Like we discussed before, they override personal project and plug-in skills with the same name. This is for mandatory standards, security requirements, compliance workflows, coding practices that must be consistent across the organization. Keyword must.

**1:54** · Here's something that surprises people.

**1:56** · Sub agents don't automatically see your skills. Yeah, when you delegate a task to a sub agent, it starts with a fresh, clean context. Built-in agents like the explorer, plan, and verify can't access skills at all. Only custom sub agents you define can use them and only when you explicitly list them. To create a custom sub agent with skills, add an agent.mmd file include/ aents. The skills field lists which skills to load.

**2:22** · These skills are loaded when the sub aent starts, not in demand like in the main conversation. So take that into consideration.

**2:30** · First ensure the skills exist.

**2:35** · Okay, it exists. Then create the sub agent using the claw code sub aent creator. If you have a sub agent that you want to add these skills to already just go to the existing agent.md file.

**2:47** · Then after that create the skills fields and add your skills. When you delegate to the sub agent it has both skills loaded and applies them to every single review.

**2:58** · Now this pattern works really well when you want isolated task delegation with specific expertise.

**3:05** · Different sub agents need different skills. Front-end reviewer versus back-end reviewer. You want to enforce standards and delegated work without relying on prompts. Only list skills that are always relevant to the subage's purpose.

**3:21** · Share skills through project directories for team access, plugins for cross repository distribution, or enterprise deployment for organizationwide standards. Sub agents don't inherit skills automatically, so list them explicitly in the sub agents skills field. Built-in agents can't access skills. Only custom sub agents can in your claw/ agents. Skills load when the sub agents start, so only list skills that are always relevant to its purpose.