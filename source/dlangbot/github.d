module dlangbot.github;

import dlangbot.bugzilla : bugzillaURL, bugzillaProjectSlugs, Issue, IssueRef;
import dlangbot.warnings : printMessages, UserMessage;

import std.algorithm, std.range;
import std.datetime;
import std.format : format, formattedWrite;
import std.typecons : Tuple;

import vibe.core.log;
import vibe.data.json;

public import dlangbot.github_api;

//==============================================================================
// Github comments
//==============================================================================

void printBugList(W)(W app, in IssueRef[] refs, in Issue[] descs)
{
    auto combined = zip(refs.map!(r => r.id), refs.map!(r => r.fixed),
                        descs.map!(d => d.severity), descs.map!(d => d.desc));
    app.put("Auto-close | Bugzilla | Severity | Description\n");
    app.put("--- | --- | --- | ---\n");
    foreach (num, closed, severity, desc; combined)
    {
        const escapedDesc = markdownEscape(desc);
        app.formattedWrite(
            "%1$s | [%2$s](%5$s/show_bug.cgi?id=%2$s) | %3$s | %4$s\n",
            closed ? "✓" : "✗", num, severity, escapedDesc, bugzillaURL);
    }
}

string markdownEscape(string desc)
{
    import std.array : appender;
    auto app = appender!string;
    foreach (c; desc)
    {
        if (c == '|') app ~= "&#124;";
        else if (c.among('\\', '*', '_', '{', '}', '[', ']', '(', ')', '#',
                       '`', '+', '-', '.', '!'))
        {
            app ~= '\\';
            app ~= c;
        }
        else
            app ~= c;
    }
    return app.data;
}

string manualChangelogURL(string repoSlug)
{
    return "https://github.com/%s/blob/master/%s".format(
        repoSlug, repoSlug == "dlang/dlang.org" ? "language-changelog" : "changelog",
    );
}

string formatComment(in ref PullRequest pr, in IssueRef[] refs, in Issue[] descs, in UserMessage[] msgs)
{
    import std.array : appender;

    auto app = appender!string;

    bool isMember = ghGetRequest(pr.membersURL ~ "?per_page=100")
        .body
        .deserializeJson!(GHUser[])
        .canFind!(l => l.login == pr.user.login);

    // Avoid actually mentioning users when referring to them
    auto userRef = `**@<!-- -->%s**`.format(pr.user.login);

    if (isMember)
    {
        app.formattedWrite(
`Thanks for your pull request, %s!
`, userRef, pr.repoSlug);
    }
    else
    {
        app.formattedWrite(
"Thanks for your pull request and interest in making D better, %s!  We are looking forward to reviewing it, and you should be hearing from a maintainer soon.
Please verify that your PR follows this checklist:

- My PR is fully covered with tests (you can see the coverage diff by visiting the _details_ link of the codecov check)
- My PR is as minimal as possible (smaller, focused PRs are easier to review than big ones)
- I have provided a detailed rationale explaining my changes
- New or modified functions have Ddoc comments (with `Params:` and `Returns:`)

Please see [CONTRIBUTING.md](https://github.com/%s/blob/master/CONTRIBUTING.md) for more information.

---

If you have addressed all reviews or aren't sure how to proceed, don't hesitate to ping us with a simple comment.",
                           userRef, pr.repoSlug);
    }

    // markdown doesn't support breaking of long lines
    if (bugzillaProjectSlugs.canFind(pr.repoSlug))
    {
        app ~= "\n### Bugzilla references\n\n";
        if (refs.length)
            app.printBugList(refs, descs);
        else
            app.formattedWrite(
`Your PR doesn't reference any Bugzilla issue.

If your PR contains non-trivial changes, please [reference a Bugzilla issue](https://github.com/dlang-bots/dlang-bot#automated-references) or create a [manual changelog](%s).
`, manualChangelogURL(pr.repoSlug));
    }

    if (msgs.length)
    {
        if (refs.length)
            app ~= "\n";
        app ~= "### ⚠️⚠️⚠️ Warnings ⚠️⚠️⚠️\n\n";
        app.printMessages(msgs);
    }
    if (pr.repoSlug.among("dlang/dmd", "dlang/druntime", "dlang/phobos", "dlang/tools"))
    {
        app.put("
### Testing this PR locally

If you don't have a [local development environment setup](https://wiki.dlang.org/Starting_as_a_Contributor), you can use [Digger](https://github.com/CyberShadow/Digger) to test this PR:

```sh
dub run digger -- build \"%s + %s#%d\"
```
".format(pr.base.ref_, pr.base.repo.get().name, pr.number));
    }
    return app.data;
}

GHComment getBotComment(in ref PullRequest pr)
{
    // the bot may post multiple comments (mention-bot & bugzilla links)
    auto res = ghGetRequest(pr.commentsURL)
        .body[]
        .find!(c => c["user"]["login"] == "dlang-bot");
    if (res.length)
        return deserializeJson!GHComment(res[0]);
    return GHComment();
}

void updateGithubComment(in ref PullRequest pr, in ref GHComment comment,
                         string action, IssueRef[] refs, Issue[] descs, UserMessage[] msgs)
{
    // The history should be preserved and modifications after a merge/closed event are seldomly seen
    if (pr.state == GHState.closed)
        return;

    logDebug("[github/updateGithubComment](%s): %s", pr.pid, refs);
    logDebug("%s", descs);
    assert(refs.map!(r => r.id).equal(descs.map!(d => d.id)));

    auto msg = pr.formatComment(refs, descs, msgs);
    logDebug("%s", msg);

    if (msg != comment.body_)
    {
        if (comment.url.length)
            comment.update(msg);
        else if (action != "closed" && action != "merged")
            comment.post(pr, msg);
    }
}


//==============================================================================
// Github Auto-merge
//==============================================================================

string labelName(GHMerge.MergeMethod method)
{
    final switch (method) with (GHMerge.MergeMethod)
    {
    case none: return null;
    case merge: return "auto-merge";
    case squash: return "auto-merge-squash";
    case rebase: return "auto-merge-rebase";
    }
}

GHMerge.MergeMethod autoMergeMethod(GHLabel[] labels)
{
    with (GHMerge.MergeMethod)
    {
        auto labelNames = labels.map!(l => l.name);
        if (labelNames.canFind!(l => l == "auto-merge"))
            return merge;
        else if (labelNames.canFind!(l => l == "auto-merge-squash"))
            return squash;
        else if (labelNames.canFind!(l => l == "auto-merge-rebase"))
            return rebase;
        return none;
    }
}

Json[] tryMerge(in ref PullRequest pr, GHMerge.MergeMethod method)
{
    import std.conv : to;
    import ae.utils.aa : OrderedSet;

    const status = pr.combinedStatus;
    if (status.state != CIState.success)
    {
        logInfo("Can't auto-merge PR %s#%d with combined CI state: %s", pr.repoSlug, pr.number, status.state);
        return null;
    }

    auto commits = ghGetRequest(pr.commitsURL).body[];

    if (!pr.isOpen)
    {
        logWarn("Can't auto-merge PR %s#%d - it is already closed", pr.repoSlug, pr.number);
        return commits;
    }

    if (commits.length == 0)
    {
        logWarn("Can't auto-merge PR %s#%d has no commits attached", pr.repoSlug, pr.number);
        return commits;
    }

    auto labelName = method.labelName;
    if (commits.length == 1)
        method = GHMerge.MergeMethod.rebase;

    auto events = ghGetRequest(pr.eventsURL).body[]
        .retro
        .filter!(e => e["event"] == "labeled" && e["label"]["name"] == labelName);

    string author = "unknown";
    if (!events.empty)
    {
        logDebug("[github/tryMerge/author](%s): %s", pr.pid, events.front["actor"]);
        author = getUserEmail(events.front["actor"]["login"].get!string);
    }

    OrderedSet!string reviewers;
    foreach (ref review; pr.reviews)
    {
        if (review.authorAssociation >= CommentAuthorAssociation.COLLABORATOR &&
            review.state == GHReview.State.APPROVED)
        {
            reviewers.add(getUserEmail(review.user.login));
        }
    }

    logDebug("[github/tryMerge/commits](%s): %s", pr.pid, commits);
    logDebug("[github/tryMerge/commitsURL](%s): %s", pr.pid, pr.commitsURL);
    logDebug("[github/tryMerge/commits](%s): %s", pr.pid, commits[$ - 1]);
    GHMerge mergeInput = {
        commitMessage: "%s\n\n%-(Signed-off-by: %s\n%|%)Merged-on-behalf-of: %s".format(
            pr.title,
            reviewers.keys,
            author),
        sha: commits[$ - 1]["sha"].get!string,
        mergeMethod: method
    };
    pr.postMerge(mergeInput);

    return commits;
}

void checkAndRemoveLabels(GHLabel[] labels, in ref PullRequest pr, in string[] toRemoveLabels)
{
    import std.uni : sicmp;
    labels
        .map!(l => l.name)
        .filter!(n => toRemoveLabels.canFind!((a, b) => sicmp(a,b) == 0)(n))
        .each!(l => pr.removeLabel(l));
}

void addLabels(in ref PullRequest pr, in string[] newLabels)
{
    import std.uni : icmp;
    auto existingLabels = ghGetRequest(pr.labelsURL)
                    .body[]
                    .map!(l => l["name"].get!string);
    auto toBeAdded = newLabels
        .filter!(l => existingLabels.filter!(a => a.icmp(l) == 0).empty);

    if (!toBeAdded.empty)
    {
        logInfo("[github/handlePR](%s): adding labels: %s", pr.pid, toBeAdded);
        ghSendRequest(HTTPMethod.POST, pr.labelsURL, toBeAdded.array);
    }
}

void removeLabel(in ref PullRequest pr, string label)
{
    import std.uri : encodeComponent;
    ghSendRequest(HTTPMethod.DELETE, pr.labelsURL ~ "/" ~ label.encodeComponent);
}

void replaceLabels(in ref PullRequest pr, string[] labels)
{
    ghSendRequest(HTTPMethod.PUT, pr.labelsURL, labels);
}

string getUserEmail(string login)
{
    auto user = ghGetRequest("%s/users/%s".format(githubAPIURL, login)).body;
    auto name = user["name"].opt!string(login);
    auto email = user["email"].opt!string(login ~ "@users.noreply.github.com");
    return "%s <%s>".format(name, email);
}

GHIssue[] getIssuesForLabel(string repoSlug, string label)
{
    return ghGetRequest("%s/repos/%s/issues?state=open&labels=%s"
                .format(githubAPIURL, repoSlug, label))
                .body
                .deserializeJson!(GHIssue[]);
}

auto getIssuesForLabels(string repoSlug, const string[] labels)
{
    // the GitHub API doesn't allow a logical OR
    GHIssue[] issues;
    foreach (label; labels)
        issues ~= getIssuesForLabel(repoSlug, label);
    issues.sort!((a, b) => a.number < b.number);
    return issues.uniq!((a, b) => a.number == b.number);
}

void searchForAutoMergePrs(string repoSlug)
{
    static immutable labels = ["auto-merge", "auto-merge-squash"];
    foreach (issue; getIssuesForLabels(repoSlug, labels))
    {
        if (!issue.isPullRequest) // TODO: query is:pr
            continue;

        auto pr = issue.pullRequest;
        if (auto method = autoMergeMethod(issue.labels))
            pr.tryMerge(method);
    }
}

/**
Allows contributors to use [<label>] messages in the title.
If they are part of a pre-defined, allowed list, the bot will add the
respective label.
*/
void checkTitleForLabels(in ref PullRequest pr)
{
    import std.algorithm.iteration : splitter;
    import std.regex;
    import std.string : strip, toLower;

    static labelRe = regex(`\[(.*)\]`);
    string[] userLabels;
    foreach (m; pr.title.matchAll(labelRe))
    {
        foreach (el; m[1].splitter(","))
            userLabels ~= el;
    }

    const string[string] userLabelsMap = [
        "trivial": "trivial",
        "wip": "WIP"
    ];

    auto mappedLabels = userLabels
                            .sort()
                            .uniq
                            .map!strip
                            .map!toLower
                            .filter!(l => l in userLabelsMap)
                            .map!(l => userLabelsMap[l])
                            .array;

    if (mappedLabels.length)
        pr.addLabels(mappedLabels);
}
