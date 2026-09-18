# Design Philosophy

## The output of a skill is something that can be measured or evaluated

A skill takes input and produces structured, inspectable output. You can tell whether it succeeded by looking at that artifact.

Examples:
**commit-formatting** → a commit message;
**pr-formatting** → PR structure;
**plan-3-approaches** → an implementation plan.

## An agent passes inputs to skills, and acts on the outputs from skills

An agent shapes requests into skill inputs, runs skills, and decides what to do next from their outputs—including refining with human feedback.

Example: 
**planner** takes a Jira ticket or prompt, shapes it for **plan-3-approaches**, gets your feedback, then refines the plan from the selected approach.
