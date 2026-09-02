---
name: implementation-philosophy
description: Core design philosophy for sustainable implementation—refactor first, enhance existing components, combine in new ways. Use when implementing features or choosing how to solve problems.
---

# Implementation Philosophy

Core design philosophy: Build applications that are easy to maintain and grow over time  Preferred ways to solve problems:
1. First refactor, extract and define new types or components, then solve by creating a new implementation of that type or component
2. Improving and enhancing an existing type or component
3. Combine existing types and components in a new way

These problem solving approaches intended to emphasize sustainable design, and to avoid changing multiple components, creating large God files and methods, and introducing cyclomatic complexity by adding new branching logic
