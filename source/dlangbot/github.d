module dlangbot.github;

string githubAPIURL = "https://api.github.com";
string githubAuth, hookSecret;

import dlangbot.bugzilla : bugzillaURL, Issue, IssueRef;

import std.algorithm, std.range;
import std.format : format;
import std.typecons : Tuple;

import vibe.core.log;
import vibe.data.json;
import vibe.http.client : HTTPClientRequest, requestHTTP;
import vibe.http.common : HTTPMethod;
import vibe.stream.operations : readAllUTF8;

//==============================================================================
// Github comments
//==============================================================================

string formatComment(R1, R2)(R1 refs, R2 descs)
{
    import std.array : appender;
    import std.format : formattedWrite;

    auto combined = zip(refs.map!(r => r.id), refs.map!(r => r.fixed), descs.map!(d => d.desc));
    auto app = appender!string();
    app.put("Fix | Bugzilla | Description\n");
    app.put("--- | --- | ---\n");

    foreach (num, closed, desc; combined)
    {
        app.formattedWrite(
            "%1$s | [%2$s](%4$s/show_bug.cgi?id=%2$s) | %3$s\n",
            closed ? "✓" : "✗", num, desc, bugzillaURL);
    }
    return app.data;
}

struct Comment { string url, body_; }

Comment getBotComment(in ref PullRequest pr)
{
    // the bot may post multiple comments (mention-bot & bugzilla links)
    auto res = ghGetRequest(pr.commentsURL)
        .readJson[]
        .find!(c => c["user"]["login"] == "dlang-bot" && c["body"].get!string.canFind("Bugzilla"));
    if (res.length)
        return deserializeJson!Comment(res[0]);
    return Comment();
}

auto ghGetRequest(string url)
{
    return requestHTTP(url, (scope req) {
        req.headers["Authorization"] = githubAuth;
    });
}

void ghSendRequest(scope void delegate(scope HTTPClientRequest req) userReq, string url)
{
    HTTPMethod method;
    requestHTTP(url, (scope req) {
        req.headers["Authorization"] = githubAuth;
        userReq(req);
        method = req.method;
    }, (scope res) {
        if (res.statusCode / 100 == 2)
        {
            logInfo("%s %s, %s\n", method, url, res.statusPhrase);
            res.bodyReader.readAllUTF8;
        }
        else
            logWarn("%s %s failed;  %s %s.\n%s", method, url,
                res.statusPhrase, res.statusCode, res.bodyReader.readAllUTF8);
    });
}

auto ghSendRequest(T...)(HTTPMethod method, string url, T arg)
    if (T.length <= 1)
{
    return ghSendRequest((scope req) {
        req.method = method;
        static if (T.length)
            req.writeJsonBody(arg);
    }, url);
}

void updateGithubComment(in ref PullRequest pr, in ref Comment comment, string action, IssueRef[] refs, Issue[] descs)
{
    logDebug("%s", refs);
    if (refs.empty)
    {
        if (comment.url.length) // delete any existing comment
            ghSendRequest(HTTPMethod.DELETE, comment.url);
        return;
    }
    logDebug("%s", descs);
    assert(refs.map!(r => r.id).equal(descs.map!(d => d.id)));

    auto msg = formatComment(refs, descs);
    logDebug("%s", msg);

    if (msg != comment.body_)
    {
        if (comment.url.length)
            ghSendRequest(HTTPMethod.PATCH, comment.url, ["body" : msg]);
        else if (action != "closed" && action != "merged")
            ghSendRequest(HTTPMethod.POST, pr.commentsURL, ["body" : msg]);
    }
}


//==============================================================================
// Github Auto-merge
//==============================================================================

struct PullRequest
{
    import std.typecons : Nullable;

    static struct Repo
    {
        @name("full_name") string fullName;
    }
    static struct Branch
    {
        Repo repo;
    }
    Branch base, head;
    enum State { open, closed }
    @byName State state;
    uint number;
    string title;
    Nullable!bool mergeable;

    string baseRepoSlug() const { return base.repo.fullName; }
    string headRepoSlug() const { return head.repo.fullName; }
    alias repoSlug = baseRepoSlug;
    bool isOpen() const { return state == State.open; }
    string commentsURL() const { return "%s/repos/%s/issues/%d/comments".format(githubAPIURL, repoSlug, number); }
    string commitsURL() const { return "%s/repos/%s/pulls/%d/commits".format(githubAPIURL, repoSlug, number); }
    string eventsURL() const { return "%s/repos/%s/issues/%d/events".format(githubAPIURL, repoSlug, number); }
    string htmlURL() const { return "https://github.com/%s/pull/%d".format(repoSlug, number); }

    static PullRequest fetch(string repoSlug, uint number)
    {
        return ghGetRequest("%s/repos/%s/pulls/%d"
                            .format(githubAPIURL, repoSlug, number))
                .readJson
                .deserializeJson!PullRequest;
    }
}

alias LabelsAndCommits = Tuple!(Json[], "labels", Json[], "commits");
enum MergeMethod { none = 0, merge, squash, rebase }

string labelName(MergeMethod method)
{
    final switch (method) with (MergeMethod)
    {
    case none: return null;
    case merge: return "auto-merge";
    case squash: return "auto-merge-squash";
    case rebase: return "auto-merge-rebase";
    }
}

MergeMethod autoMergeMethod(Json[] labels)
{
    auto labelNames = labels.map!(l => l["name"].get!string);
    if (labelNames.canFind!(l => l == "auto-merge"))
        return MergeMethod.merge;
    else if (labelNames.canFind!(l => l == "auto-merge-squash"))
        return MergeMethod.squash;
    else if (labelNames.canFind!(l => l == "auto-merge-rebase"))
        return MergeMethod.rebase;
    return MergeMethod.none;
}

auto handleGithubLabel(in ref PullRequest pr)
{
    auto url = "%s/repos/%s/issues/%d/labels".format(githubAPIURL, pr.repoSlug, pr.number);
    auto labels = ghGetRequest(url).readJson[];

    Json[] commits;
    if (auto method = labels.autoMergeMethod)
        commits = pr.tryMerge(method);

    return LabelsAndCommits(labels, commits);
}

Json[] tryMerge(in ref PullRequest pr, MergeMethod method)
{
    import std.conv : to;

    auto commits = ghGetRequest(pr.commitsURL).readJson[];

    if (!pr.isOpen)
    {
        logWarn("Can't auto-merge PR %s/%d - it is already closed", pr.repoSlug, pr.number);
        return commits;
    }

    if (commits.length == 0)
    {
        logWarn("Can't auto-merge PR %s/%d has no commits attached", pr.repoSlug, pr.number);
        return commits;
    }

    auto labelName = method.labelName;
    auto events = ghGetRequest(pr.eventsURL).readJson[]
        .retro
        .filter!(e => e["event"] == "labeled" && e["label"]["name"] == labelName);

    string author = "unknown";
    if (!events.empty)
        author = getUserEmail(events.front["actor"]["login"].get!string);

    auto reqInput = [
        "commit_message": "%s\nmerged-on-behalf-of: %s".format(pr.title, author),
        "sha": commits[$ - 1]["sha"].get!string,
        "merge_method": method.to!string,
    ];


    auto prUrl = "%s/repos/%s/pulls/%d/merge".format(githubAPIURL, pr.repoSlug, pr.number);
    ghSendRequest((scope req){
        req.method = HTTPMethod.PUT;
        // custom media type is required during preview period:
        // https://developer.github.com/changes/2016-09-26-pull-request-merge-api-update/
        req.headers["Accept"] = "application/vnd.github.polaris-preview+json";
        req.writeJsonBody(reqInput);
    }, prUrl);

    return commits;
}

void checkAndRemoveLabels(Json[] labels, in ref PullRequest pr, in string[] toRemoveLabels)
{
    labels
        .map!(l => l["name"].get!string)
        .filter!(n => toRemoveLabels.canFind(n))
        .each!(l => pr.removeLabel(l));
}

void addLabels(in ref PullRequest pr, inout string[] labels)
{
    auto labelUrl = "%s/repos/%s/issues/%d/labels"
            .format(githubAPIURL, pr.repoSlug, pr.number);
    ghSendRequest(HTTPMethod.POST, labelUrl, labels);
}

void removeLabel(in ref PullRequest pr, string label)
{
    auto labelUrl = "%s/repos/%s/issues/%d/labels/%s"
        .format(githubAPIURL, pr.repoSlug, pr.number, label);
    ghSendRequest(HTTPMethod.DELETE, labelUrl);
}

string getUserEmail(string login)
{
    auto user = ghGetRequest("%s/users/%s".format(githubAPIURL, login)).readJson;
    auto name = user["name"].get!string;
    auto email = user["email"].opt!string(login ~ "@users.noreply.github.com");
    return "%s <%s>".format(name, email);
}

Json[] getIssuesForLabel(string repoSlug, string label)
{
    return ghGetRequest("%s/repos/%s/issues?state=open&labels=%s"
                .format(githubAPIURL, repoSlug, label)).readJson[];
}

void searchForAutoMergePrs(string repoSlug)
{
    // the GitHub API doesn't allow a logical OR
    auto issues = getIssuesForLabel(repoSlug, "auto-merge").chain(getIssuesForLabel(repoSlug, "auto-merge-squash"));
    issues.sort!((a, b) => a["number"].get!int < b["number"].get!int);
    foreach (issue; issues.uniq!((a, b) => a["number"].get!int == b["number"].get!int))
    {
        auto prNumber = issue["number"].get!uint;
        if ("pull_request" !in issue)
            continue;

        PullRequest pr;
        pr.base.repo.fullName = repoSlug;
        pr.number = prNumber;
        pr.state = PullRequest.State.open;
        pr.title = issue["title"].get!string;
        if (auto method = autoMergeMethod(issue["labels"][]))
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

auto getPassingCiCount(string repoSlug, string sha)
{
    auto json = ghGetRequest("%s/repos/%s/status/%s"
                            .format(githubAPIURL, repoSlug, sha))
                .readJson["statuses"][];
    return json.filter!((e){
         if (e["state"] == "success")
             switch (e["context"].get!string) {
                 case "auto-tester":
                 case "CyberShadow/DAutoTest":
                 case "continuous-integration/travis-ci/pr":
                 case "ci/circleci":
                     return true;
                 default:
                     return false;
             }
         return false;
    }).walkLength;
}

/**
Marks a PR as reviewable if
- there hasn't been a review yet
- there is at least one successful CI
*/
void checkPRForReviewNeed(string repoSlug, Json statusPayload)
{
    import dlangbot.ci : getPRForStatus;

    import std.stdio;
    auto passingCi = getPassingCiCount(repoSlug, statusPayload["sha"].get!string);

    auto prNumber = getPRForStatus(repoSlug,
                                   statusPayload["target_url"].get!string,
                                   statusPayload["context"].get!string);

    if (!prNumber.isNull)
    {
        PullRequest pr = {number: prNumber};
        pr.base.repo.fullName = repoSlug;
        logInfo("repo(%s): found a valid PR number: %d", repoSlug, prNumber);
        auto reviewsURL = "%s/repos/%s/pulls/%d/reviews"
                          .format(githubAPIURL, repoSlug, prNumber);
        auto reviews = requestHTTP(reviewsURL, (scope req) {
                // custom media type is required during preview period:
                // preview review api: https://developer.github.com/changes/2016-12-14-reviews-api
                req.headers["Accept"] = "application/vnd.github.black-cat-preview+json";
                req.headers["Authorization"] = githubAuth;
            })
            .readJson[];

        if (reviews.length == 0 && passingCi >= 2)
        {
            logInfo("repo(%s): No review found", repoSlug);
            // do the cool stuff here
            pr.addLabels(["needs review"]);
        }
        else if (reviews.length > 0)
        {
            pr.removeLabel("needs review");
        }
    }
}
