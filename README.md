# Dlang-Bot

[![Travis build status](https://travis-ci.org/dlang/dlang-bot.svg?branch=master)](https://travis-ci.org/dlang/dlang-bot)
[![Codecov](https://img.shields.io/codecov/c/github/dlang/dlang-bot/master.svg)](https://codecov.io/gh/dlang/dlang-bot)

<img alt="dlang-bot" height="200px" src="public/img/dlang_bot.png" />

Features
--------

- [Automated bugzilla, github, and trello references](#automated-references)
- [Auto-merging approved & passing PRs](#auto-merge)
- [Warn about common mistakes](#warn-common-mistakes)
- [Find stalled PRs](#stalled-prs)
- [Allow PR submitters to label their PRs](#user-tagging)
- [Send contributing advice message](#hello-contributor)
- [Auto-label PRs](#auto-labelling)
- [Using the Dlang-Bot for your project](#dlang-bot-for-your-project)
- [Missing a feature?](#missing-a-feature)

<a name="automated-references" />

Automated references
--------------------

For example let's say you fixed [Issue 16582](https://issues.dlang.org/show_bug.cgi?id=16582)
and make a PR for on GitHub.
If one of your commits mentions the issue, e.g. like this Git commit message:

```
fix Issue 16582 - ParameterDefaults fails w/ scope parameter
```

The Dlang-Bot will do all the hard work of linking and referencing
between Bugzilla, GitHub and Trello do for you.

### GitHub

It would comment on GitHub with list of all mentioned issues and link them to Bugzilla:

<img alt="dlang-bot-github" height="120px" src="public/img/dlang_bot_github_comment.png" />

The first column of the table is the current status of the referenced issue.
A `✗` means that the issue is only mentioned (i.e. the commit message doesn't contain "Fix")
and the Bugzilla issue won't be auto-closed nor listed in the changelog as fixed:

![image](https://user-images.githubusercontent.com/4370550/27858949-7e9dd862-6177-11e7-9ba2-764c919f7a78.png)

### Trello

For the [Trello board](https://trello.com/b/XoFjxiqG/active) it will also provide a
reference:

<img alt="dlang-bot-trello" height="120px" src="public/img/dlang_bot_trello_comment.png" />

And once a PR gets merged, the bot moves the linked Trello card to "Testing / Review".

### Bugzilla

Once a PR has been merged (i.e. the commits got pushed to master or stable),
GitHub's Bugzilla integration will automatically comment to Bugzilla with a regarding commit:

<img alt="dlang-bot-bugzilla" height="120px" src="public/img/dlang_bot_bugzilla_comment.png" />

It will also automatically close the referenced issues if `fix` or `fixes` (case-insensitive)
appears before the issue reference.

Using this syntax is also very important because for the changelog generation, the
git history will be used. Thus _only_ if the Dlang-Bot has detected an issue
and commented on your PR it can become part of the changelog.

In doubt, you can use e.g. [Regex101](https://regex101.com/r/aI0Rp6/7) to validate your commit message.

### Referencing multiple issues

It's possible to reference multiple issues, e.g. with "Fixes issues 17494, 17505, 17506" the Dlang-Bot would detect:

![image](https://user-images.githubusercontent.com/4370550/27887078-2322e06e-61df-11e7-85cd-4cd5648e0139.png)

Accepted optional separators are: commas (`,`), the word `and`, as well as the plus sign (`+`),
and any amount of whitespace. Dlang-Bot will aggregate all mentioned issues over multiple commits.

### Nerdy details

- one can mention multiple issues in one commit and/or multiple commits
- the exact RegEx is:

```
(?:^fix(?:es)?(?:\s+(?:issues?|bugs?))?\s+(#?\d+(?:[\s,\+&and]+#?\d+)*))|(?:(?:issues?|bugs?)\s+(#?\d+(?:[\s,\+&and]+#?\d+)*))
```

(the GitHub Bugzilla integration and the Dlang-Bot use the same RegEx to parse
git commit messages)

<a name="auto-merge" />

Auto-merge (WIP)
---------------

At the moment the Dlang-Bot supports merging via special `auto-merge` and
`auto-merge-squash` labels. The later will perform a squashed merge of all commits
in the PR into a single one.

A reviewer can toggle a PR for "auto-merge" by simply adding the `auto-merge` label
(`auto-merge-squash` respectively).


### Nerdy details

- this relies on the "restricted branches" feature of GitHub (the Dlang-Bot will
send the attempt to merge to the GitHub API)
- once a new commit event occurs (push, synchronization) the Dlang-Bot will
automatically remove set all auto-merge labels from the PR
- for status events the GitHub API doesn't allow to get an information about the
- the Dlang-Bot will then try to restart the PR on every new event.
- concerning PR of the commit (thus all potential auto-merge PRs are checked)

_Note_: at the moment the Dlang-Bot doesn't store _any_ authentication token, so
it can't perform actions on behalf of others.

<a name="warn-common-mistakes" />

Warn about common mistakes
--------------------------

The Dlang-Bot will try to detect common mistakes and warn the contributor.
Currently implemented:
- Regression fixes doesn't target `stable`

![image](https://user-images.githubusercontent.com/4370550/27756953-604dfb36-5dfc-11e7-9d15-6ed8f747dada.png)

<a name="stalled-prs" />

Find stalled PRs
----------------

The Dlang-Bot goes over all pull requests every day and will label PRs:

- ["stalled"](https://github.com/dlang/phobos/issues?q=is%3Aopen+is%3Apr+label%3Astalled) (PR has had no activity within 60 days)
- ["needs rebase"](https://github.com/dlang/phobos/issues?q=is%3Aopen+is%3Apr+label%3A%22needs+rebase%22) (PR has a merge conflict)
- ["needs work"](https://github.com/dlang/phobos/issues?q=is%3Aopen+is%3Apr+label%3A%22needs+work%22) (PR has more than two failing CI providers)

Currently this feature is in alpha-mode and only enabled for Phobos.

<a name="user-tagging" />

Allow PR submitters to label their PRs
---------------------------------------

Dlang-Bot detects a pre-defined set of labels in the `[]` part of PR title and will label the PRs accordingly.
Multiple labels are supported.

![image](https://user-images.githubusercontent.com/4370550/27757037-4d116368-5dfd-11e7-8df4-1446473f9d01.png)

![image](https://user-images.githubusercontent.com/4370550/27757033-3ea63a7e-5dfd-11e7-95ab-c0f36521dc63.png)

Currently the hard-coded set of detected labels is:
- WIP
- trivial

<a name="hello-contributor" />

Send contributing advice message
---------------------------------

For all repos in the `dlang` organization Dlang-Bot provides contributing advice on a new PR:

![image](https://user-images.githubusercontent.com/4370550/27757092-c237063e-5dfd-11e7-8aab-7e655aea3ac8.png)

<a name="auto-labelling" />

Auto-label PRs
---------------

If a PR contains [Bugzilla references](#automated-references), the Dlang-Bot will automatically add a respective label:

![image](https://user-images.githubusercontent.com/4370550/27757121-1aa8a6f6-5dfe-11e7-97ad-240756f0c608.png)

Of course, other issue types can be detected as well:

![image](https://user-images.githubusercontent.com/4370550/27757177-bb944cdc-5dfe-11e7-8c40-26a7eb536700.png)

<a name="#dlang-bot-for-your-project" />

Using the Dlang-Bot for your project
------------------------------------

@dlang-bot responds to GitHub events sent to its webhook.
To use the bot in your project, configure a webhook with the following settings:

- Payload URL: `https://bot.dlang.io/github_hook` (or your own instance)
- Content type: `application/json`
- Select at least these events (or all): 
  - Label
  - Pull request
  - Pull request review
  - Pull request comment
  - Status

For `auto-merge`:
- a respective label needs to be added (at the `dlang` repositories `#d3d3d3` is used as a label color)
- `@dlang-bot` (or your own bot) needs to have write access to the GitHub repo (GitHub's protected branches are ideal for this)

For example, `dlang/phobos` is configured as follows:

![image](https://user-images.githubusercontent.com/4370550/27859920-b418a38e-617a-11e7-9ff2-c1fd9f6fdd20.png)

<a name="missing-a-feature" />

Improve the bot
---------------

Run the testsuite:

```
dub test -- --single --debug --trace
```

Missing a feature?
------------------

Is there a feature that you would love the Dlang-Bot to do? Then don't hesistate to let us know and [open a new issue](https://github.com/dlang/dlang-bot/issues/new).
