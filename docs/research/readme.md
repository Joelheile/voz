# Researching the voz README

Three parts: 20 sources on writing great READMEs, the pi README structure, and Joel's writing voice from joels.tech. Ends with a style brief.

## Part 1: 20 sources on writing great READMEs

1. **[GitHub Docs, "About READMEs"](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)**: A README should say what the project does, why it's useful, how to get started, where to get help, and who maintains it; push longer material to a wiki.
2. **[makeareadme.com](https://www.makeareadme.com/)**: Write the README first, before sharing the project. Favor thoroughness ("too long is better than too short") but move extensive detail to a wiki; cover name, description, badges, visuals, install, usage, support, roadmap, contributing, authors, license, status.
3. **[Richard Litt, standard-readme spec](https://github.com/RichardLitt/standard-readme)**: A README is the entry point: explain why someone would use the module and how to install and use it without reading the source. Its own table of contents orders sections as Background, Install, Usage, API, Contributing, License.
4. **[matiassingers/awesome-readme](https://github.com/matiassingers/awesome-readme)**: Good READMEs use images/GIFs, a table of contents, clear install/usage sections, and community sections (contributing, license, credits); an ARCHITECTURE.md covering diagrams and invariants is called "essential" for larger projects.
5. **[Diátaxis](https://diataxis.fr/)**: Documentation splits into four distinct forms matched to four needs: tutorials (learning), how-to guides (tasks), reference (information), explanation (understanding). A README usually mixes several of these in miniature, which is fine at that scale, but longer docs should separate them.
6. **[Google developer documentation style guide](https://developers.google.com/style)**: Apply project style first, then the guide, then outside references (Merriam-Webster, Chicago Manual of Style); depart from the guide when it improves clarity, but stay consistent once you do.
7. **[opensource.guide, "Starting a project"](https://opensource.guide/starting-a-project/)**: Answer four questions: what does this do, why is it useful, how do I get started, where can I get help. State directly if the project isn't production-ready or isn't accepting contributions.
8. **[Tom Preston-Werner, "Readme Driven Development"](https://tom.preston-werner.com/2010/08/23/readme-driven-development.html)**: Write the README before any code. It forces you to design the interface and your motivation while it's highest, and gives a concrete artifact for others to react to.
9. **[noffle, "Art of README"](https://github.com/hackergrrl/art-of-readme)** (mirror; original 404s): widely cited for arguing a README should open with what the thing is and why it matters before anything else, then get the reader running code in the first few lines. It's the source other guides (e.g. common-readme) point back to.
10. **[Write the Docs, beginner's guide](https://www.writethedocs.org/guide/writing/beginners-guide-to-docs/)**: Write for two audiences: users (want to use it) and developers (want to contribute). Keep install steps to a few lines with a link for detail. Don't let a FAQ substitute for real docs.
11. **[Simon Willison, on docs](https://simonwillison.net/2022/Nov/26/productivity/)**: Keep docs in the repo, not a wiki, so they version with the code; update docs in the same commit as the change so reviewers catch drift; every new project gets a README and tests from the start.
12. **[Jacob Kaplan-Moss, "What to write"](https://jacobian.org/series/great-documentation/)**: No single format works for all readers, since people learn differently; a well-documented project offers several forms (overview, walkthrough, reference) rather than one.
13. **[Divio documentation system](https://docs.divio.com/documentation-system/)**: Tutorials, how-to guides, reference, and explanation serve different purposes and should not be blended in one document; a document trying to do all four serves none of them well.
14. **[opensource.guide](https://opensource.guide/starting-a-project/)** is listed above at #7; **[freeCodeCamp, "How to write a good README file"](https://www.freecodecamp.org/news/how-to-write-a-good-readme-file/)**: Answer what/why/how, add a one-sentence title, use badges from shields.io sparingly, show screenshots and login credentials if auth is needed, and keep the README updated as the project changes.
15. **[ripgrep README](https://github.com/BurntSushi/ripgrep)**: Opens with a one-paragraph definition, then badges and doc links, a screenshot, heavy benchmark tables, and an explicit "why you should/shouldn't use this" section before a long per-platform install list. Direct, opinionated, first-person, self-deprecating in places.
16. **[fzf README](https://github.com/junegunn/fzf)**: Badges and a banner, one-line pitch, four bolded highlight bullets, then a deep table of contents before install. Uses Note/Tip/Warning callouts. Install is organized by platform, with shell integration documented separately per shell.
17. **[uv README](https://github.com/astral-sh/uv)**: Badges, one-line tagline, a benchmark chart image immediately after, then bulleted highlights making bold speed claims. Install shown as copy-paste shell blocks per OS. Ends with an FAQ (pronunciation, capitalization) and acknowledgements.
18. **[Bun README](https://github.com/oven-sh/bun)**: Centered logo, badges, a short "What is Bun?" with a one-line definition and an immediate code block. Install is one command per method (script, npm, Homebrew, Docker). Most of the file's length is a nested link index to external docs, not prose.
19. **[Raycast extensions README](https://github.com/raycast/extensions)**: Opens with "Raycast lets you control your tools with a few keystrokes," pitches the product (not the individual extensions), and routes contributors to API docs and the Store. Short, friendly, no feature list.
20. **[pi-mono README](https://github.com/badlogic/pi-mono)**: see Part 2 below for full detail. Opens with a one-line positioning statement and a mission statement about adapting the tool to your workflow, not the other way around.

### Synthesis: 10 rules most sources agree on

1. Open with what it is and why it matters, in one or two sentences, before anything else.
2. Get the reader to a working result (install + first command) within the first screen.
3. Favor a working example with real output over abstract description.
4. State install steps explicitly and literally: assume the reader is a stranger, not a contributor.
5. Keep it in the repo, versioned with the code, not in a wiki that drifts out of date.
6. Say plainly what it doesn't do, isn't ready for, or won't accept (contributions, production use) rather than staying silent.
7. Don't blend tutorial, reference, and explanation in one long README. Link out to docs for depth instead (Diátaxis's core point, echoed by Bun, uv, and pi).
8. Use visuals (screenshot, GIF, chart) only when they demonstrate behavior, not as decoration.
9. Badges belong near the top, used sparingly: status/version/community links, not decoration.
10. License, contributing, and support channel are expected even when terse. Their absence reads as abandonment.

### What a SHORT README must contain vs. what belongs in docs/

**Short README (first screen, maybe two):**

- One-line identity: what it is.
- One-paragraph pitch: why it matters / what makes it different.
- Install (copy-pasteable).
- First-run / minimal usage example.
- Link to full docs, extension/package system, or contributing guide.
- License line.

**Belongs in docs/ instead:**

- Full command/API reference.
- Every platform's install variant and troubleshooting.
- Architecture, invariants, and design-decision writeups (ARCHITECTURE.md or docs/design.md, which voz already has).
- FAQ, benchmarks, and extended feature walkthroughs.
- Contribution process detail, supply-chain/security hardening notes.

## Part 2: pi README (Mario Zechner, badlogic/pi-mono)

Fetched the live README at `github.com/badlogic/pi-mono` (root of the monorepo, the project is named "Pi," and is installed as `@earendil-works/pi-coding-agent`).

### Opening lines, verbatim

```
> New issues and PRs from new contributors are auto-closed by default. Maintainers review auto-closed issues daily. See CONTRIBUTING.md.

# Pi

Pi is a minimal, extensible agent harness that you can make your own.

Adapt Pi to your workflows, not the other way around. Customize Pi with extensions, skills, prompt templates, and themes. Bundle them as Pi packages and share via npm or git.

Pi ships with powerful defaults but skips features like sub-agents and plan mode. Ask Pi to build what you want, or install a package that does it your way.

Use Pi interactively, automate it in print or JSON mode, control it over RPC, or build apps with the Pi TypeScript SDK. See OpenClaw for a real-world integration.
```

### Structure (section order)

1. Logo (centered image linking to pi.dev) + two badges (Discord, npm version).
2. A blockquote callout about contributor PR auto-closing, pointing to CONTRIBUTING.md. Sets expectations before the pitch even starts.
3. `# Pi`: title, then one-sentence definition.
4. Positioning paragraph ("Adapt Pi to your workflows...") naming every extension point with inline links.
5. A sentence on what Pi deliberately omits (sub-agents, plan mode) and how to get it anyway (ask it to build, or install a package).
6. A sentence on the four ways to run it (interactive, print/JSON, RPC, SDK), each linked, plus a pointer to a real integration (OpenClaw).
7. "Getting started": curl/PowerShell installer one-liners, npm alternative with a note about why the installer is safer (dependency pinning), Node version requirement, `cd` + `pi` + `/login`, then a link to full docs.
8. "Run with Nix."
9. "Packages": a table of every monorepo package with one-line descriptions.
10. "Permissions & Containerization": explicit statement that Pi has no built-in sandboxing, with three named isolation patterns.
11. "Contributing" links to CONTRIBUTING.md, AGENTS.md, and the RFCs page.
12. "Development": build/check/test commands.
13. "Using local packages outside the monorepo," "Building standalone binaries from release source," "Supply-chain hardening": contributor/maintainer depth.
14. "Share your OSS coding agent sessions": a product/community ask, with a linked X post and a Hugging Face dataset.
15. "License": MIT, one word.
16. Footer: credit for the pi.dev domain donation, with the exe.dev mascot image.

### Tone, length, install, extension pitch

- **Length:** long (~200 lines), but the first ~40 lines are the entire pitch and quick start; everything after "Packages" is contributor/maintainer depth.
- **Tone:** confident, terse, declarative sentences. No marketing adjectives ("blazingly fast," "powerful," etc.). It plainly states what the tool does and doesn't do instead. The honesty move ("Pi does not include a built-in permission system... By default, it runs with the permissions of the user and process that launched it") stands out: most tool READMEs bury limitations, but pi states them as a numbered section with named mitigations.
- **Install:** two code blocks (curl|sh, PowerShell irm|iex), then an npm fallback with a one-sentence tradeoff explanation (pinning vs. not). No OS-specific package manager list like ripgrep/fzf. It funnels everyone through one installer.
- **Extensions/packages pitch:** folded into the second paragraph of the pitch itself, not a separate marketing section. Every noun (extensions, skills, prompt templates, themes, packages) is a link straight to its doc page. The pitch is "adapt it to you," not "look at all these features."
- **Images/badges:** minimal, just one logo, two badges, one footer mascot image. No screenshots, no GIFs, no benchmark charts (pi doesn't compete on a numeric claim the way ripgrep/uv do).

What makes it good: it leads with philosophy (one sentence of identity, one sentence of principle) before any command, states its own limits as plainly as its features, and treats "the four ways to run me" and "the four ways to extend me" as the real content of the pitch. Install comes after the reader already knows why they'd bother.

## Part 3: Joel's writing style (joels.tech)

Fetched the live homepage (Astro-rendered, single page: `/about`, `/projects`, `/blog` all return 308 redirects back to the homepage, so there is no separate page to fetch). Also fetched his GitHub profile README (`github.com/Joelheile/Joelheile`) as a second sample, since it's clearly written in the same voice.

### Representative sentences, verbatim

From joels.tech:

1. "Hi, I'm Joël :)"
2. "I'm a founder, product engineer and community builder."
3. "Currently building Attacal: AI agents that attack your app every day and open a pull request for every hole they find, so you never have to think about security again."
4. "I started a YouTube channel at 10 with Minecraft mod tutorials and tech reviews."
5. "At 14 I founded a web dev and video agency that made €20k+ while I was still in high school."
6. "Later I studied computer science at CODE University and did ML at Stanford."
7. "Next to uni, I automated the finances of a marketing agency and tried out lots of my own startup ideas."
8. "With Lore we built AI agents and a data pipeline that analyzed 1.2M+ TikTok and Instagram videos for Nike and Mastercard."
9. "Most recently, I built and shipped an AI meeting notetaker at SF Consumer Lab in two weeks and made $4k in revenue within four weeks of starting."
10. "At 16 I ran a podcast asking founders where they failed and met other 16 year olds on LinkedIn."
11. "In three years I scaled the team from 5 to 100+ volunteers."
12. "Today it's Germany's largest community for founders under 25."
13. "If you're building something interesting, I'd like to hear about it :)"

From the GitHub profile README (same voice, lowercase title): 14. "hi, i'm joël :)" 15. "founder and product engineer. building Attacal: AI agents that attack your app every day and open a pull request for every hole they find." 16. "AI meeting notetaker: bot free desktop app for mac and windows. shipped in two weeks, 200 paying customers and $4k revenue within four weeks." 17. "YBudget: open source budget software for german associations. the YFN team now runs the whole NGO on it."

### Concrete style description

- **Sentence length:** short, almost all single-clause or two-clause. The longest sentences are lists of what happened ("X at 14, Y at Stanford, Z next"), joined with "and," not subordinate clauses.
- **Person:** first person singular ("I started," "I founded," "I built") for his own work; first person plural ("we built," "we have 2,200+ members") for team/company work. Never addresses the reader as "you" in the bio; the one exception is the Attacal pitch line ("so you never have to think about security again"), where "you" is the product's user.
- **Tone:** plain, factual, resume-like but warm. No hype adjectives on himself ("passionate," "innovative"). The one place hype creeps in is describing the product (Attacal: "attack your app every day"), not himself.
- **Humor:** minimal and soft. A smiley ":)" appears twice (greeting, closing), never a joke or wordplay in the prose itself.
- **Capitalization:** the website capitalizes normally ("Hi, I'm Joël"); the GitHub README is fully lowercase, including the title and his own name ("hi, i'm joël :)", "building Attacal"). Treat lowercase as a GitHub/dev-context register, not a universal rule.
- **Punctuation:** periods end nearly every sentence. Colons introduce the thing being built ("Currently building Attacal:", "AI meeting notetaker: bot free desktop app..."). Em dashes do not appear. Numbers are always concrete and specific (€20k+, 1.2M+, 2,200+, $4k, 200 paying customers), never rounded vaguely ("a lot of users").
- **How he describes projects:** formula is [what it is] plus [concrete proof number]. "shipped in two weeks, 200 paying customers and $4k revenue within four weeks" follows timeframe, outcome, number, always in that order (built, then shipped, then result). Never describes a project by its tech stack first; always by what it does for someone, then the number that proves it worked.
- **Words he favors:** "shipped," "built," "founded," "scaled," concrete role nouns (founder, engineer, community builder), exact dollar/count figures.
- **Words he avoids:** no "leverage," "robust," "seamless," "cutting-edge," "passionate," "revolutionize." None of the standard self-promotion vocabulary appears anywhere on the page.
- **Headline/title style:** short noun-phrase self-descriptions ("founder, product engineer and community builder"), not taglines with wordplay.

## Style brief for the voz README

1. Open with one sentence of identity ("voz is the fastest, most reliable, simplest and most extensible voice transcriber") and one sentence of principle, the way pi opens with "Pi is a minimal, extensible agent harness" plus "Adapt Pi to your workflows, not the other way around." voz's CLAUDE.md already has this line. Reuse it verbatim, don't rewrite it into something flashier.
2. State what voz deliberately doesn't do, the way pi states "Pi does not include a built-in permission system." For voz: no sandboxing for extensions, no theme packages yet, no webview UI. Say it plainly, don't bury it.
3. Fold the extension pitch into the identity paragraph itself, not a separate marketing section. One sentence naming the extension points (events, UI primitives, settings schema), each linked to its doc, the way pi links extensions/skills/prompt-templates/themes inline.
4. Install goes right after the pitch, as a single copy-pasteable command, no OS-by-OS package manager list (voz is one app, closer to Bun/pi's single-installer approach than to ripgrep/fzf's 25-manager list).
5. First-run example immediately after install: the one sentence that gets someone dictating, not a feature tour.
6. Use Joel's number-first proof style sparingly but concretely where it's true (e.g. "zero extensions installed costs zero startup time" rather than "optimized for performance"). Specific and verifiable, never a vague superlative.
7. No hype adjectives. Never say "seamless," "powerful," "cutting-edge." If a claim needs backing, back it with a fact or a number, not an adjective.
8. Keep sentences short and declarative, mostly single-clause, matching both pi's terse style and Joel's own. Avoid subordinate-clause sentences entirely in the opening section.
9. Push everything past the first screen into docs/: full extension API reference, every settings field, troubleshooting, and architecture rationale belong in docs/extensions.md, docs/design.md, etc., not the README.
10. End with the plain, low-key sign-off register Joel uses ("If you're building something interesting, I'd like to hear about it") rather than a marketing CTA. License line, link to docs, maybe one line inviting extension authors, then stop.
