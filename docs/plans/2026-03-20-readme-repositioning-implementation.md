# README Repositioning Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reposition the public chart README as a compelling product landing page, normalize `RtBot` naming, and preserve fast install comprehension for new users.

**Architecture:** Keep the README in one file, but reorder it from marketing-to-technical: value proposition and quick start first, then verification, then configuration/reference. Normalize the chart documentation wording to `RtBot` where it appears as product naming.

**Tech Stack:** Markdown, grep-based terminology check, Helm README only plus any small related chart docs if needed.

---

### Task 1: Rework the README structure and naming

**Files:**
- Modify: `README.md`
- Modify: `templates/NOTES.txt` if wording needs matching

**Step 1: Write the failing check**

Run:

```bash
grep -R "RTBot\|RTBOT" README.md templates/NOTES.txt
```

Expected: old capitalization appears.

**Step 2: Rewrite the README**

Make the top of the document answer these questions immediately:

- What does the coprocessor do?
- Why would a ThingsBoard user want it?
- What is the fastest install command?
- How do I know it worked?

Use a short table of contents only if it materially improves scanability.

**Step 3: Re-run the naming check**

Run the same grep command.

Expected: public-facing `RTBot` references are normalized to `RtBot`.

**Step 4: Commit**

```bash
git add README.md templates/NOTES.txt docs/plans/2026-03-20-readme-repositioning-design.md docs/plans/2026-03-20-readme-repositioning-implementation.md
git commit -m "docs: reposition chart readme for new users"
```
