module dlangbot.warnings;

import dlangbot.bugzilla : Issue, IssueRef;
import dlangbot.github : PullRequest, manualChangelogURL;

import std.algorithm;

struct UserMessage
{
    enum Type { Error, Warning, Info }
    Type type;

    string text;
}


void checkEnhancementChangelog(in ref PullRequest pr, ref UserMessage[] msgs,
        in Issue[] bugzillaIssues, in IssueRef[] refs)
{
    import dlangbot.utils : request, expectOK;
    import vibe.stream.operations : readAllUTF8;
    import std.format : format;

    if (bugzillaIssues.any!(i => i.status.among("NEW", "ASSIGNED", "REOPENED") &&
                                 i.severity == "enhancement" &&
                                 refs.canFind!(r => r.id == i.id && r.fixed)))
    {
        auto diff = request(pr.diffURL).expectOK.bodyReader.readAllUTF8;
        if (!diff.canFind("\n+++ b/changelog/"))
        {
            msgs ~= UserMessage(UserMessage.Type.Warning,
                "Pull requests implementing enhancements should include a [full changelog entry](%s)."
                .format(manualChangelogURL(pr.repoSlug))
            );
        }
    }
}


/**
Check bugzilla priority
- enhancement -> changelog entry
- regression/major -> stable
*/
void checkBugzilla(in ref PullRequest pr, ref UserMessage[] msgs,
        in Issue[] bugzillaIssues, in IssueRef[] refs)
{
    // check for stable
    if (pr.base.ref_ != "stable")
    {
        if (bugzillaIssues.any!(i => i.status.among("NEW", "ASSIGNED", "REOPENED") &&
                                     (i.severity.among("critical", "blocker", "regression") ||
                                      i.keywords.splitter(", ").canFind("ice")) &&
                                     refs.canFind!(r => r.id == i.id && r.fixed)))
        {
            msgs ~= UserMessage(UserMessage.Type.Warning,
                "Regression or critical bug fixes should always target the `stable` branch." ~
                " Learn more about [rebasing to `stable`](https://wiki.dlang.org/Starting_as_a_Contributor#Stable_Branch) or" ~
                " the [D release process](https://github.com/dlang/DIPs/blob/master/DIPs/archive/DIP75.md#branching-strategy)." ~
                "\n\nTo target `stable` perform these two steps:\n\n" ~
                "1) Rebase your branch to `upstream/stable`:\n\n" ~
                "```sh
git rebase --onto upstream/stable upstream/master
```\n\n" ~
                "2) [Change the base branch of your PR to `stable`](https://blog.github.com/2016-08-15-change-the-base-branch-of-a-pull-request)"
                );
        }
    }
}


UserMessage[] checkForWarnings(in PullRequest pr, in Issue[] bugzillaIssues, in IssueRef[] refs)
{
    UserMessage[] msgs;
    pr.checkBugzilla(msgs, bugzillaIssues, refs);
    pr.checkEnhancementChangelog(msgs, bugzillaIssues, refs);
    return msgs;
}

void printMessages(W)(W app, in UserMessage[] msgs)
{
    foreach (msg; msgs)
    {
        app ~= "- ";
        app ~= msg.text;
        app ~= "\n";
    }
}
