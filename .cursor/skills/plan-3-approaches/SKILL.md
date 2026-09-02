---
name: plan-3-approaches
description: Generates three approaches to add new behavior—staff/architect, quick delivery, and wild card. Use when planning implementation options for a feature or Jira ticket.
---

# Plan 3 Approaches

Generate 3 approaches to add the new behavior

# Approach 1
Thoughtful, as if done by a staff engineer or architect with a deep understanding of the system. This can include refactorings, to make the code easier to change, so that the implementation ends up being less code.

Bias is simple, easy to support and grow. Prefer shaping the code, extracting new components, thinking about the overall design.
Example: refactor to define a new interface, existing code uses a base implementation, and then solve by creating a new implementation

# Approach 2
Quick and dirty, not introducing any bugs or serious performance issues, but not necessarily considering the larger design of the system. As if done by a senior engineer, trying to get this delivered quickly, with the chance to clean it up later

# Approach 3
Wild card - an interesting or novel approach, as if done by a really talented engineer with a broad range of experiences. Something that works, and works well, but may not be obvious to other engineers on the team.
