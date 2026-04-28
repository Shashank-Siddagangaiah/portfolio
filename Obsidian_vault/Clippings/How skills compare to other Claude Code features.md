---
title: "How skills compare to other Claude Code features"
source: "https://www.youtube.com/watch?v=IgNN4v0BJdU&list=PLmWCw1CzcFim_hkruZSlABOUOAAQ5JMyo&index=4"
author:
  - "[[Claude]]"
published: 2026-02-19
created: 2026-04-27
description: "Claude Code offers several customization options: Skills, CLAUDE.md, subagents, hooks, and MCP servers. They solve different problems, and knowing when to use each prevents you from building the wrong"
tags:
  - "clippings"
---
![](https://www.youtube.com/watch?v=IgNN4v0BJdU)

Claude Code offers several customization options: Skills, CLAUDE.md, subagents, hooks, and MCP servers. They solve different problems, and knowing when to use each prevents you from building the wrong thing. Browse all courses and learn more: claude.com/resources/courses

## Transcript

**0:02** · Claw Code offers several customization options. Skills, claw.md, sub aents, hooks, MCP servers. They solve different problems. Knowing when to use each prevents you from building the wrong thing. So, let's run them down.

**0:18** · Cloud.md loads into every conversation always. So, if you want claude to use TypeScript strict mode in this project, then put it in your cloud. MD file skills load on demand. When Claude matches a request, your PR review checklist doesn't need to be in the context when you're writing a new code.

**0:38** · It activates when you ask for a review.

**0:42** · So, use Claude MD for project-wise standards that always apply constraints like never modify the database schema, framework preferences, and coding style.

**0:53** · Then use skills for task specific expertise, knowledge that's only relevant sometimes, and detailed procedures that would clutter every conversation.

**1:04** · Skills add knowledge to your current conversation. When a skill activates, its instructions join the existing context. Sub aents run in a separate context. They receive a task, work on it independently, and return results.

**1:18** · They're isolated from your main conversation. Use sub agents when you want to delegate a task to a separate execution context. You need different tool access that the main conversation does. You want isolation between delegated work and your main context.

**1:34** · Use skills when you want to enhance cla's knowledge for the current task.

**1:37** · The expertise applies throughout a conversation.

**1:42** · Hooks fire on events. A hook might run a llinter every time Claude saves a file or validate input before certain tool calls. They're all event driven, while skills, they're request driven. They activate based on what you're asking. So use hooks for operations that should run on every file save, validation before specific tool calls, or automated side effects of clause actions. Then use skills for knowledge that informs how claw handles requests, guidelines that affect clause reasoning.

**2:15** · A typical setup might include a claw.md file for always on project standards, skills for task specific expertise, hooks for automated operations. Each handles its own specialty. Don't force everything into skills when another option fits best. You can use multiple at a time.

**2:34** · Skills provide automatic task specific expertise. CloudMD is for always on instructions. Sub aents run in isolated context. \[music\] Hooks fire on events.

**2:45** · MCP provides external tools. Use skills when you have knowledge that Claude should apply automatically when the topic is relevant and combine them with other features for comprehensive customization.