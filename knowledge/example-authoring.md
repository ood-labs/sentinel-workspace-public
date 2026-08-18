# Example Authoring and Reuse

The projects in `projects/` are finished teaching references. Use them to learn
how Sentinel graphs are structured, how data contracts move between nodes, and
how a complete project packages its dependencies. They are not a stock module
library.

## Start from the user's problem

Before authoring a graph, identify:

- the meaningful source or authored generator;
- the analysis or transformation the work actually needs;
- the mapping from live data to visible form;
- the motion and interaction language;
- the visual direction appropriate to the subject;
- the proof that will show the result works.

Invent the smallest graph that serves those needs. Do not default to the style,
node names, layout, or module implementation of an example. A scientific
instrument, editorial collage, spatial editor, and performance visual should
look and behave differently because they solve different problems.

## How to use examples

Choose references in proportion to the problem. Begin with the strongest skill
fixture or project match, and open more only when each one answers a specific
unresolved question. Familiar single-node work may need one fixture. Complex or
novel systems may benefit from several project references. Avoid enumerating or
recursively reading the full collection. Begin authoring once the architecture,
data contracts, and proof approach are clear, then return to references when a
real implementation gap appears.

For project-level research, use `knowledge/EXAMPLE-MAP.md` to select the best
match before inspecting its relevant README sections and saved graph. Learn from:

- graph architecture and responsibility boundaries;
- typed video and data connections;
- camera, editor, and durable-state ownership;
- performance and portability decisions;
- proof and diagnostic techniques.

Reimplement the needed idea for the current project with names, controls,
visual language, and data contracts suited to that project. Do not copy a
project-bundled Module into another project unless the user explicitly asks to
fork, remix, or extend that exact example.

Reusing modules already authored in the user's current project is normal when
they remain the right abstraction. The restriction is against silently treating
the curated example collection as a stock component catalog.

## What may be shared

Generic infrastructure may be copied into a project when it has no creative
identity of its own. Examples include a neutral UI scaffold, a licensed font
table, common camera helpers, and low-level math or animation primitives.
Vendor those files into the project so the project remains portable, preserve
license notices, and include only files reached by the project's manifests and
shader includes.

Project-specific generators, renderers, layouts, palettes, interaction models,
and compositors are authored work, not shared infrastructure.

## Portable project contract

A public example must:

1. keep every active Module under its own `projects/<project>/modules/` tree;
2. use relative `modules/<name>` paths in saved pipelines;
3. include only active modules and their recursive include dependencies;
4. keep every required runtime asset inside the project;
5. put required third-party licenses beside the files they cover;
6. exclude captures, review media, caches, recovery data, credentials, and
   maintainer notes;
7. explain every source, pipeline, output, important connection, interaction,
   engine dependency, and remix seam in its README;
8. compile and load from a clean checkout without relying on another project.

Static validation proves packaging and structure. A finished creative example
also needs live health, rising frame counts, meaningful previews, working
interactions, and output review in the running Sentinel build.
